# Cloud Service Model: KijaniKiosk

## Decision: PaaS for the core platform
KijaniKiosk serves small retailers. Its API processes product orders and payments, the engineering team is small, and the current pain is operational: monthly releases, weekend war rooms, and incidents after release. The goals are to serve customers quickly, minimise outages, and keep costs predictable.

The deciding question is who manages which layers.

| Layer | IaaS | PaaS | SaaS |
|---|---|---|---|
| Application | KijaniKiosk | KijaniKiosk | Provider (configured by us) |
| Runtime / middleware | KijaniKiosk | Provider | Provider |
| Operating system | KijaniKiosk | Provider | Provider |
| Compute / storage / network | Provider (configured by us) | Provider (configured by us) | Provider |
| Physical infrastructure | Provider | Provider | Provider |

Under PaaS, KijaniKiosk owns application code, application configuration, data management, and performance optimisation. The provider owns the operating system, runtime, and scaling infrastructure.

## Why PaaS fits
1. It removes the work that causes the current pain. Patching, capacity planning, and manual scaling take engineering time and make releases heavy. On a managed platform a release is a new application version pushed to a managed runtime, which supports smaller and more frequent releases (Flow).
2. The team is small. The hidden cost of IaaS is system administration: patch management, capacity planning, and runtime maintenance. That effort is better spent on features for retailers.
3. Scaling is handled by the platform, so demand spikes do not need a manual response.

## Why not IaaS
IaaS gives the most control, but KijaniKiosk has no requirement today that needs OS-level control. Choosing it would mean accepting operational work with no matching benefit.

## Why not SaaS
KijaniKiosk is the product. The team must deploy and control its own application code, which SaaS does not allow.

## Benefit and limitation
- Benefit: less operational work, so the team can release more often and with less coordination.
- Limitation: less control over the runtime and operating system, dependence on the platform's supported languages and features, some lock-in, and platform outages that the team cannot fix itself.

## Responsibilities that stay with KijaniKiosk
PaaS does not make the system secure by default. The team still owns application security, access control (see `iam-least-privilege.md`), data protection, network layout (see `network-topology.md`), and monitoring of its own application. The provider patching the OS does not replace these.

## Where other models still appear
- SaaS for supporting tools such as email, dashboards, and monitoring. Card payment handling is worth delegating to a specialist payment provider (SaaS) instead of building it, because it reduces the sensitive data the platform handles directly.
- IaaS-level building blocks for the network. This starter kit creates a VPC, subnets, and route tables directly, because network segmentation is a design decision the team owns even when the application runs on a managed platform. The diagram shows tiers (web, app, database), not server types. On a managed platform the same tiers are placed in the same subnets.

## When to revisit this decision
- A component needs an unsupported runtime or OS-level customisation: move that component to IaaS.
- Platform cost grows beyond the cost of running the workload directly.
- A compliance requirement needs control the platform does not offer.
