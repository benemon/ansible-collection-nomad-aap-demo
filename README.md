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
| `deploy_worker.yml` | Registers or purges a heartbeat worker with no exposed ports, in a chosen node pool |
| `templates/worker.nomad.hcl.j2` | The worker's jobspec: a Python loop that writes a counter and timestamp to `/tmp/heartbeat` every 5 seconds |
| `verify_worker.yml` | Runs inside the worker's allocations over the `benemon.nomad.nomad_exec` connection and checks the heartbeat advances |
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

The policy allows submitting, reading, listing and exec into jobs in `default`,
and reading nodes for the inventory plugin.

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

## Heartbeat worker

`deploy_worker.yml` runs a worker that opens no ports. Its variables are
`job_name` (default `heartbeat`), `node_pool` (default `default`) and
`job_state`.

`verify_worker.yml` targets the inventory group `nomad_job_<job_name>`, so
the inventory has to be synced after the worker is deployed; *Update on
launch* on the inventory source does that. For each allocation it reads the
heartbeat, waits for the counter to advance, writes the allocation ID into the
task and reads it back. Pass the same `job_name` to both playbooks; a name
with characters other than letters, digits and underscores is sanitised in
the group name.

The checks use `ansible.builtin.raw`. Modules send their payload over stdin,
and the podman driver never closes stdin in an exec session, so a module
task waits until it times out.
