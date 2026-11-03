# Week 8 Friday Reflection

> Draft. Edit these in your own words before submitting.

## 1. Automating the whole sequence in the Week 5 Jenkinsfile

The hardest step to make reliable would be the deploy-and-verify step, not the build or push. Build and push are deterministic: the same commit produces the same image and the same `<semver>-<git-sha>` tag, and a failure there is loud. Deploying is asynchronous. `kubectl apply` returns as soon as the API accepts the manifest, not when the Pods are serving, so the job has to wait on `kubectl rollout status` with a timeout and then probe `/health` and compare the version field with the tag it just pushed. The failure mode that worries me most is a silent mismatch: the manifest still pointing at an older tag (or a placeholder), the rollout "succeeding" because the old Pods are still healthy, and the pipeline going green while the new build never runs. A second concern is credentials on the Jenkins agent: the Docker Hub token would have to be injected with `withCredentials`, used only for `docker login --password-stdin`, followed by `docker logout` in a `post { always }` block, so it never lingers on the agent between runs.

## 2. One sentence, rewritten for Tendo

Plain language (for Nia): "When we deliberately removed one running copy of the service, a replacement was running and ready in N seconds. The second copy kept answering customers the whole time."

Technical (for Tendo): "After `kubectl delete pod` on one of the two replicas, the ReplicaSet created a replacement that reached `Running` and `1/1 Ready` N seconds later; the NodePort Service kept routing to the surviving endpoint and the 1-second health probe saw no non-200 responses."

What is the same: the number, and the claim that service continued. What is lost in the plain version: which component did the work (the ReplicaSet controller), how "ready" was defined (container started and passing, not just scheduled), and how we know customers were not affected (a probe through the Service, not real traffic). What is gained: Nia can repeat it to the board accurately without having to explain controllers or endpoints, and the number stays tied to evidence she can point to.

## 3. Hardcoded values that belong in a ConfigMap or Secret

- **`NODE_ENV=production`**: differs per environment. Hardcoding it means staging runs with production behaviour, or we keep two copies of the manifest that drift apart. ConfigMap.
- **`PORT=3001`** (and the matching `containerPort`): a runtime setting, not part of the workload's identity. Changing it today needs a manifest edit and a rollout. ConfigMap.
- **The image registry and namespace (`docker.io/<user>/...`)**: environment-specific if staging and production use different registries or accounts. Better templated per environment (Kustomize overlay or Helm value) than edited by hand.
- **Resource requests and limits**: production and a laptop cluster need different values. Hardcoding them either starves production or over-reserves on minikube. Per-environment overlay.
- **Registry credentials**: already correctly in a Secret (`kijani-registry-credentials`) and referenced by name, which is the pattern every future credential (database URL, payment provider key) must follow. Putting any of those as plain `env` values would commit them to Git, the same mistake as a password in a Jenkinsfile.
