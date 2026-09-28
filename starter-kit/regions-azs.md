# Region and Availability Zone Architecture: KijaniKiosk

## Region selection
Most KijaniKiosk customers are in Kenya and neighbouring East African countries. Distance affects response time because every request and response crosses physical network links, and each extra kilometre and network hop adds latency. For a platform that processes orders and payments, slow responses are visible to retailers and their customers.

Shortlist:
1. `af-south-1` (Cape Town): the closest AWS region to East Africa on the continent. It is an opt-in region and must be enabled in the account settings before use.
2. `eu-west-1` (Ireland): a mature region with broad service coverage. It is included as a comparison point and as the alternative if Cape Town is not practical.

Principle: choose the region closest to the primary users, and confirm it with measurements rather than map distance.

Data residency: if Kenyan data protection requirements apply to retailer or customer data, confirm where that data may be stored before finalising the region. This could favour keeping data in Africa.

## Latency evidence
Measured from a machine in Nairobi (fill in from your own terminal):

```bash
ping -c 5 ec2.af-south-1.amazonaws.com
ping -c 5 ec2.eu-west-1.amazonaws.com
traceroute ec2.af-south-1.amazonaws.com
```

| Endpoint | Average round trip (ms) | Hops |
|---|---|---|
| af-south-1 | TBD | TBD |
| eu-west-1 | TBD | TBD |

Observation: TBD (state which region responded faster and whether it matches the distance-based expectation).

## Multi-AZ design
Production runs across at least two availability zones in the chosen region. An availability zone is an isolated data center with independent power, networking, and cooling, so a single facility failure does not take the platform down.

Components that must be replicated across zones for the system to stay available:
- Application tier, spread across zones behind a load balancer
- Database, with a standby replica in a second zone and automatic failover
- Load balancer, deployed into the public subnet of each zone
- Stored data, since object storage replicates across zones by default

## Failure walkthrough
Scenario: the data center hosting zone A loses power.
- Single-zone deployment: the application goes offline until power is restored. Retailers cannot process orders.
- Multi-zone deployment: the load balancer stops sending traffic to zone A, the database standby in zone B is promoted, and zone B keeps serving requests with reduced capacity. Autoscaling can restore capacity in zone B.

This is the reliability gain the design buys: a data center failure becomes a capacity problem instead of an outage.

## Implemented and planned
The network built for this project contains one public and one private subnet in zone A. The diagram also shows the matching subnets in zone B as planned, since multi-AZ needs both zones. Adding them is the same procedure repeated in a second zone with different CIDR blocks.

## Why not multi-region yet
Multi-region protects against a whole-region outage, but it adds data replication, consistency trade-offs, higher cost, and harder operations. It does not remove outages. It moves the failure modes into replication and deployment complexity.

Multi-region is justified when:
- business continuity or regulation requires surviving a full regional outage, or
- users are spread across distant continents and one region cannot give acceptable latency.

Recommendation: start with multi-AZ in one region, which covers the most likely failure (a single data center) at manageable cost. Revisit multi-region when user geography or continuity requirements demand it.
