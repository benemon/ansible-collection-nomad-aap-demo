# benemon.nomad on Ansible Automation Platform

One playbook, `deploy_container.yml`, runs a container image as a Nomad
service job on the podman task driver. The image is an extra var, so a single
job template deploys any container. AAP runs it in a custom execution
environment carrying `benemon.nomad`, and an inventory source built from the
collection's inventory plugin lists the Nomad clients and allocations.

| Path | What it is |
|---|---|
| `execution-environment.yml` | ansible-builder v3 definition: AAP 2.7 `ee-minimal-rhel9` plus `benemon.nomad` and `nomadpy[exec]` |
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
ansible-builder build -t ee-nomad
```

Push the image to a registry AAP can pull from.

## Nomad

```
nomad acl policy apply aap-demo nomad/aap-demo.policy.hcl
nomad acl token create -name aap-demo -type client -policy aap-demo
```

The policy allows submitting, reading and listing jobs in `default`, and reading
nodes for the inventory plugin.

## AAP

The play expects AAP to hold:

- a credential type of kind *Cloud* with the inputs and injectors in
  `aap/nomad-credential-type.yml`, and a credential of that type. The
  injectors set `NOMAD_ADDR`, `NOMAD_TOKEN` and `NOMAD_CACERT`, which every
  plugin in the collection reads when its own options are unset;
- the execution environment built above;
- this repository as a project;
- an inventory source *Sourced from a Project* on `inventory/cluster.nomad.yml`,
  with the Nomad credential and the execution environment;
- a job template on `deploy_container.yml` with the Nomad credential, the
  execution environment and *Prompt on launch* for variables.

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
