# benemon.nomad on Ansible Automation Platform

One playbook, `deploy_container.yml`, runs a container image as a Nomad
service job on the podman task driver. The image is an extra var, so a single
job template deploys any container. AAP runs it in a custom execution
environment carrying `benemon.nomad`, and an inventory source built from the
collection's inventory plugin lists the Nomad clients and allocations.

| Path | What it is |
|---|---|
| `execution-environment.yml` | ansible-builder v3 definition: AAP 2.7 `ee-minimal-rhel9` plus `benemon.nomad` and `nomadpy[exec]` |
| `openshift/ee-build.yaml` | ImageStream and binary Docker BuildConfig that build the EE inside the cluster |
| `deploy_container.yml` | Registers or purges the job and reports each running allocation's address |
| `templates/container.nomad.hcl.j2` | The jobspec: one group, one podman task, a dynamic port mapped to `container_port` |
| `inventory/cluster.nomad.yml` | `benemon.nomad.nomad` inventory: client nodes and the allocations of the `default` namespace |
| `nomad/aap-demo.policy.hcl` | ACL policy for the token AAP uses |
| `aap/nomad-credential-type.yml` | Inputs and injectors of the AAP credential type that carries the Nomad connection |

## Execution environment

`benemon.nomad` requires ansible-core 2.19, newer than the 2.16 in the AAP 2.7
base image, so the definition installs ansible-core 2.19 from PyPI over it.
Red Hat does not support that combination. registry.redhat.io serves no
`latest` tag, so the base image is pinned by digest.

```
ansible-builder create -c context
oc apply -f openshift/ee-build.yaml
oc start-build ee-nomad -n aap --from-dir=context --follow
```

The image lands at `image-registry.openshift-image-registry.svc:5000/aap/ee-nomad:latest`,
which AAP pods in the same namespace pull without a registry credential.

## Nomad

```
nomad acl policy apply aap-demo nomad/aap-demo.policy.hcl
nomad acl token create -name aap-demo -type client -policy aap-demo
```

The policy allows submitting, reading and listing jobs in `default`, and reading
nodes for the inventory plugin. The HTTP API needs the cluster CA but no client
certificate.

## AAP

1. Credential type **Nomad**, kind *Cloud* so it can be attached to an
   inventory source: paste the inputs and injectors from
   `aap/nomad-credential-type.yml`. The injectors set `NOMAD_ADDR`,
   `NOMAD_TOKEN` and `NOMAD_CACERT`, which every plugin in the collection reads
   when its own options are unset.
2. Credential of that type: the address, the `aap-demo` token's secret ID, and
   the CA.
3. Execution environment: the image above.
4. Project: this repository.
5. Inventory with a source *Sourced from a Project*, file
   `inventory/cluster.nomad.yml`, the Nomad credential and the execution
   environment.
6. Job template: inventory above, playbook `deploy_container.yml`, the Nomad
   credential and the execution environment, with *Prompt on launch* for
   variables.

Launch it with:

```yaml
job_name: demo-nginx
container_image: docker.io/library/nginx:alpine
```

and again with another `job_name` and `container_image` for a second
container. `job_state: absent` with the same `job_name` stops and purges the
job. Optional variables are `container_port` (default `80`) and `instances`
(default `1`).

The play runs on `localhost` and talks only to the Nomad API; the inventory
is there to show the cluster from AAP and is not a target of this play.
