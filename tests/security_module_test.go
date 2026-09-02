package test

import (
	"fmt"
	"strings"
	"testing"

	"github.com/aws/aws-sdk-go/aws"
	ec2sdk "github.com/aws/aws-sdk-go/service/ec2"
	ttaws "github.com/gruntwork-io/terratest/modules/aws"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testRegion = "eu-north-1"

// Real apply/destroy contract test for the security module. Security groups and
// a VPC are free and create in seconds. It asserts the least-privilege chain:
// alb-sg is open to the internet on :80, app-sg only trusts alb-sg on :8080,
// db-sg only trusts app-sg on :5432, and neither app-sg nor db-sg has any raw
// CIDR ingress.
func TestSecurityModuleChainedGroups(t *testing.T) {
	t.Parallel()

	project := fmt.Sprintf("tt-sg-%s", strings.ToLower(random.UniqueId()))
	opts := &terraform.Options{
		TerraformDir: "./fixtures/security",
		Vars:         map[string]interface{}{"project": project},
		EnvVars:      map[string]string{"AWS_DEFAULT_REGION": testRegion},
		NoColor:      true,
	}

	defer terraform.Destroy(t, opts)
	terraform.InitAndApply(t, opts)

	albID := terraform.Output(t, opts, "alb_sg_id")
	appID := terraform.Output(t, opts, "app_sg_id")
	dbID := terraform.Output(t, opts, "db_sg_id")
	require.NotEmpty(t, albID)
	require.NotEmpty(t, appID)
	require.NotEmpty(t, dbID)

	client := ttaws.NewEc2Client(t, testRegion)
	out, err := client.DescribeSecurityGroups(&ec2sdk.DescribeSecurityGroupsInput{
		GroupIds: aws.StringSlice([]string{albID, appID, dbID}),
	})
	require.NoError(t, err)

	byID := map[string]*ec2sdk.SecurityGroup{}
	for _, sg := range out.SecurityGroups {
		byID[aws.StringValue(sg.GroupId)] = sg
	}
	alb, app, db := byID[albID], byID[appID], byID[dbID]
	require.NotNil(t, alb)
	require.NotNil(t, app)
	require.NotNil(t, db)

	assert.True(t, hasCidrIngress(alb, 80, "0.0.0.0/0"),
		"alb-sg must allow TCP 80 from 0.0.0.0/0")

	assert.True(t, hasSourceGroupIngress(app, 8080, albID),
		"app-sg must allow TCP 8080 from alb-sg")
	assert.False(t, hasAnyCidrIngress(app),
		"app-sg must not allow any CIDR ingress")

	assert.True(t, hasSourceGroupIngress(db, 5432, appID),
		"db-sg must allow TCP 5432 from app-sg")
	assert.False(t, hasAnyCidrIngress(db),
		"db-sg must not allow any CIDR ingress")
}

func hasCidrIngress(sg *ec2sdk.SecurityGroup, port int64, cidr string) bool {
	for _, p := range sg.IpPermissions {
		if p.FromPort == nil || *p.FromPort != port {
			continue
		}
		for _, r := range p.IpRanges {
			if aws.StringValue(r.CidrIp) == cidr {
				return true
			}
		}
	}
	return false
}

func hasSourceGroupIngress(sg *ec2sdk.SecurityGroup, port int64, srcGroupID string) bool {
	for _, p := range sg.IpPermissions {
		if p.FromPort == nil || *p.FromPort != port {
			continue
		}
		for _, g := range p.UserIdGroupPairs {
			if aws.StringValue(g.GroupId) == srcGroupID {
				return true
			}
		}
	}
	return false
}

func hasAnyCidrIngress(sg *ec2sdk.SecurityGroup) bool {
	for _, p := range sg.IpPermissions {
		if len(p.IpRanges) > 0 || len(p.Ipv6Ranges) > 0 {
			return true
		}
	}
	return false
}
