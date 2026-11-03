# Week 7 and Week 8 Delivery: What Changed and Why It Matters

**For:** Nia, ahead of Monday's board presentation
**From:** Valencia Neema

## The short version

In Week 7 we copied the payments service onto a server prepared in advance and kept two versions side by side, so customers could be moved back to the old one if the new one misbehaved. In Week 8 the service ships as a sealed package that carries everything it needs, stored in a private, versioned library, and a system keeps two copies running at all times and replaces any copy that fails, without anyone being paged.

Two measured results from this week's evidence:

- **Recovery without a person:** when we deliberately removed one running copy of the service, a replacement was running and ready in **about 1 second**. The second copy kept answering customers the whole time: all 8 test requests sent during the swap succeeded.
- **A smaller package:** the first, unoptimised package was **281.8 MB**. The production package is **86.6 MB**, a **69% reduction**.

## Side by side

| Concern | Week 7 approach (blue/green on a virtual machine) | Week 8 approach (containers on Kubernetes) |
|---|---|---|
| **Deployment mechanism** | A deploy script fetched a versioned tarball, unpacked it into the idle environment (blue on port 3000 or green on port 3001) and restarted its systemd unit. Node.js, users and directories had to exist on the VM already, put there by Ansible. | A multi-stage Dockerfile builds an image that contains Node.js and the app. The image is pushed to a private Docker Hub repository with an immutable `<semver>-<git-sha>` tag, and a Deployment manifest declares which tag should run. |
| **Rollback mechanism** | `rollback.sh` rewrites the nginx include file to point back at the previous environment and reloads nginx. A post-deploy monitor triggers it after three failed health checks; the design target was under 90 seconds. | Change the image tag in the Deployment back to the previous version and apply it (or `kubectl rollout undo`). Every previous version stays in the registry under its own tag, so any earlier build can be redeployed, not only the last one. |
| **Failure recovery** | systemd restarts a crashed process on the same VM. If the VM itself fails, both environments are lost until someone provisions and configures a new server. | The Deployment controller keeps 2 replicas. A deleted or crashed Pod is replaced automatically (about 1 s measured), while the Service keeps routing to the healthy replica. |
| **Scaling** | Adding capacity means provisioning another VM, running Ansible on it, deploying the tarball and updating the proxy. Each environment is fixed to one port on one machine. | Change `replicas` and apply. Resource requests and limits (64Mi to 256Mi memory, 100m to 500m CPU per Pod) let the scheduler place new copies safely and stop one copy from starving the others. |

## What this means for the business

**The server no longer has to be prepared perfectly.** In Week 7, a new server only worked if exactly the right software was already installed on it, and small differences between servers made the same release behave differently. In Week 8 the service brings its own runtime, so the same package behaves the same way everywhere.

**Failures repair themselves, not just releases.** Week 7's automatic rollback protected us during a release. It did not help if a healthy service crashed on an ordinary afternoon. Week 8 watches the service all the time: when one copy disappears a new one starts within seconds, and the second copy keeps serving customers meanwhile.

**Every version is accounted for.** Each package is labelled with its version number and the exact code change it came from, and labels are never reused. We can say precisely which code was running at any moment and return to any earlier version.

**Smaller and safer to ship.** The production package holds only what the service needs to run; the build and test tools are left behind. It moves between machines faster and gives an attacker fewer pieces to exploit. The service runs as a restricted user, and the password for the private library is held by the platform, never written into our files.

## What Week 8 does not yet solve

This is not yet a production-complete setup, and it should not be presented as one. Settings that differ between testing and production are still written into the deployment file, so promoting a release still means editing it by hand. The platform currently decides a copy is ready as soon as it starts, not when it can actually take payments, so a slow-starting copy could briefly receive customers before it is able to serve them. Our measurements come from a single-machine practice environment, so recovery from losing a whole machine has been designed for but not demonstrated, and the access point we used is suitable for testing only. Building, publishing and deploying are still separate manual steps. Week 9 addresses the first three: it moves environment settings and secrets out of the deployment file into managed configuration, adds readiness checks so customers only reach copies that are truly ready, and introduces a proper controlled entry point for outside traffic.
