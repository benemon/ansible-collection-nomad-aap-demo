# benemon.nomad on Ansible Automation Platform

One playbook, `deploy_container.yml`, runs a container image as a Nomad
service job on the podman task driver. The image is an extra var, so a single
job template deploys any container. AAP runs it in a custom execution
environment carrying `benemon.nomad`, and an inventory source built from the
collection's inventory plugin lists the Nomad clients and allocations.

| Path | What it is |
|---|---|
| `execution-environment.yml` | ansible-builder v3 definition: AAP 2.7 `ee-minimal-rhel9` plus `benemon.nomad` and `nomadpy[exec]` |
| `deploy_container.yml` | Registers the job and reports each running allocation's address |
| `templates/container.nomad.hcl.j2` | The jobspec: one group, one podman task, a dynamic port mapped to `container_port` |
| `deploy_worker.yml` | Registers a heartbeat worker with no exposed ports, in a chosen node pool |
| `templates/worker.nomad.hcl.j2` | The worker's jobspec: a shell loop on the exec driver that writes a counter and timestamp to `/local/heartbeat` every 5 seconds |
| `verify_worker.yml` | Runs inside the worker's allocations over the `benemon.nomad.nomad_exec` connection and checks the heartbeat advances |
| `remove_job.yml` | Stops any job, waits for its allocations to stop, then purges it |
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
container. Optional variables are `container_port` (default `80`) and
`instances` (default `1`). `remove_job.yml` removes the job.

The play runs on `localhost` and talks only to the Nomad API. The inventory
is there to show the cluster from AAP and is not a target of this play.

## Heartbeat worker

`deploy_worker.yml` runs a worker that opens no ports. Its variables are
`job_name` (default `heartbeat`) and `node_pool` (default `default`).

`verify_worker.yml` targets the inventory group `nomad_job_<job_name>`, so
the inventory has to be synced after the worker is deployed. *Update on
launch* on the inventory source does that. For each allocation it reads the
heartbeat file and waits for the counter to advance. Pass the same `job_name`
to both playbooks. Characters other than letters, digits and underscores in
the name are sanitised in the group name.

The worker runs on the exec driver, so the modules use the client's own
`/usr/bin/python3` through the task's chroot. On the podman driver an exec
session never sees the end of stdin, which is how modules receive their
payload, so module tasks there wait until they time out. `ansible.builtin.raw`
still works there.

## Removing a job

`remove_job.yml` takes `job_name` and works on any job, whatever its driver
or node pool. It stops the job and waits until none of its allocations is
pending or running, so every task exits within its own `kill_timeout`. Then
it purges the job. A job that does not exist is left as it is, with no error.
