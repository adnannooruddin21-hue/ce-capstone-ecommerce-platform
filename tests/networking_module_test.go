package test

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Plan-only contract test for the networking module. It creates nothing (and so
// costs nothing): it runs `terraform plan` and asserts the shape of what the
// module *would* build — the VPC CIDR and the two-public / two-private subnet
// layout. Needs read-only AWS credentials because the module reads
// `data.aws_availability_zones`.
func TestNetworkingModulePlan(t *testing.T) {
	t.Parallel()

	opts := &terraform.Options{
		TerraformDir: "./fixtures/networking",
		Vars: map[string]interface{}{
			"project": fmt.Sprintf("tt-net-%s", strings.ToLower(random.UniqueId())),
		},
		PlanFilePath: filepath.Join(t.TempDir(), "plan.tfplan"),
		NoColor:      true,
	}

	plan := terraform.InitAndPlanAndShowWithStruct(t, opts)

	vpc, ok := plan.ResourcePlannedValuesMap["module.networking.aws_vpc.this"]
	require.True(t, ok, "module should plan a VPC named aws_vpc.this")
	assert.Equal(t, "10.20.0.0/16", vpc.AttributeValues["cidr_block"],
		"VPC CIDR should be 10.20.0.0/16")

	public, private := 0, 0
	for addr := range plan.ResourcePlannedValuesMap {
		switch {
		case strings.Contains(addr, "aws_subnet.public"):
			public++
		case strings.Contains(addr, "aws_subnet.private"):
			private++
		}
	}
	assert.Equal(t, 2, public, "expected 2 public subnets (one per AZ)")
	assert.Equal(t, 2, private, "expected 2 private subnets (one per AZ)")
}
