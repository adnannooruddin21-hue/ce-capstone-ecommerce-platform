hey -z 30s -c 10 "http://$ALB/api/products"   

Summary:
  Total:        30.0620 secs
  Slowest:      0.3225 secs
  Fastest:      0.0486 secs
  Average:      0.0662 secs
  Requests/sec: 150.8218
  
  Total data:   7163720 bytes
  Size/request: 1580 bytes

Response time histogram:
  0.049 [1]     |
  0.076 [4041]  |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.103 [387]   |■■■■
  0.131 [50]    |
  0.158 [37]    |
  0.186 [9]     |
  0.213 [4]     |
  0.240 [3]     |
  0.268 [0]     |
  0.295 [1]     |
  0.322 [1]     |


Latency distribution:
  10% in 0.0543 secs
  25% in 0.0585 secs
  50% in 0.0638 secs
  75% in 0.0693 secs
  90% in 0.0769 secs
  95% in 0.0857 secs
  99% in 0.1386 secs

Details (average, fastest, slowest):
  DNS+dialup:   0.0001 secs, 0.0000 secs, 0.0392 secs
  DNS-lookup:   0.0000 secs, 0.0000 secs, 0.0089 secs
  req write:    0.0000 secs, 0.0000 secs, 0.0009 secs
  resp wait:    0.0660 secs, 0.0484 secs, 0.3222 secs
  resp read:    0.0001 secs, 0.0000 secs, 0.0073 secs

Status code distribution:
  [200] 4534 responses


--------------------------------------------------------------

hey -z 180s -c 80 "http://$ALB/api/products"    

Summary:
  Total:        181.3527 secs
  Slowest:      1.9024 secs
  Fastest:      0.0444 secs
  Average:      0.5252 secs
  Requests/sec: 151.7044
  
  Total data:   43468960 bytes
  Size/request: 1580 bytes

Response time histogram:
  0.044 [1]     |
  0.230 [15977] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  0.416 [456]   |■
  0.602 [813]   |■■
  0.788 [1651]  |■■■■
  0.973 [899]   |■■
  1.159 [572]   |■
  1.345 [967]   |■■
  1.531 [5212]  |■■■■■■■■■■■■■
  1.717 [794]   |■■
  1.902 [170]   |


Latency distribution:
  10% in 0.0528 secs
  25% in 0.0593 secs
  50% in 0.0841 secs
  75% in 1.2913 secs
  90% in 1.4318 secs
  95% in 1.4893 secs
  99% in 1.6585 secs

Details (average, fastest, slowest):
  DNS+dialup:   0.0002 secs, 0.0000 secs, 0.0800 secs
  DNS-lookup:   0.0001 secs, 0.0000 secs, 0.0360 secs
  req write:    0.0000 secs, 0.0000 secs, 0.0107 secs
  resp wait:    0.5248 secs, 0.0442 secs, 1.9023 secs
  resp read:    0.0001 secs, 0.0000 secs, 0.0097 secs

Status code distribution:
  [200] 27512 responses

