# benemon.nomad on Ansible Automation Platform

Playbooks that run Nomad workloads from AAP with the `benemon.nomad`
collection. `deploy_container.yml` runs any container image as a service job
on the podman driver. The image is a launch variable. `deploy_worker.yml`
and `verify_worker.yml` run a worker on the exec driver and check it from
inside its allocations over the `nomad_exec` connection. `remove_job.yml`
removes any job.

| Path | Purpose |
|---|---|
| `execution-environment.yml` | ansible-builder v3 definition of the execution environment |
| `deploy_container.yml` | Registers a container job and reports each running allocation's address |
| `templates/container.nomad.hcl.j2` | Jobspec for `deploy_container.yml` |
| `deploy_worker.yml` | Registers the heartbeat worker in a chosen node pool |
| `templates/worker.nomad.hcl.j2` | Jobspec for `deploy_worker.yml` |
| `verify_worker.yml` | Checks the worker's heartbeat from inside each allocation |
| `remove_job.yml` | Stops a job, waits for its allocations to stop, and purges it |
| `inventory/cluster.nomad.yml` | Inventory source: client nodes and the allocations of the `default` namespace |
| `nomad/aap-demo.policy.hcl` | ACL policy for the token AAP uses |
| `aap/nomad-credential-type.yml` | Inputs and injectors of the AAP credential type |

## Prerequisites

- A Nomad cluster with ACLs enabled, and a management token to create the
  policy and the token below.
- The podman task driver on the clients that run `deploy_container.yml` jobs.
- The exec task driver on the clients that run the worker, with
  `/usr/bin/python3` on the host.
- AAP 2.7, and a container registry AAP can pull from.

## Setup

1. Build the execution environment and push it to the registry.

   ```
   ansible-builder build -t ee-nomad
   ```

   The definition starts from the AAP 2.7 `ee-minimal-rhel9` image, pinned
   by digest because registry.redhat.io serves no `latest` tag. That image
   ships ansible-core 2.16 and `benemon.nomad` needs 2.19, so the definition
   installs ansible-core 2.19 from PyPI over it. Red Hat does not support
   that combination. See the
   [AAP life cycle](https://access.redhat.com/support/policy/updates/ansible-automation-platform).
   nomadpy comes in through the collection's `requirements.txt`.

2. Create the policy and the token AAP uses.

   ```
   nomad acl policy apply aap-demo nomad/aap-demo.policy.hcl
   nomad acl token create -name aap-demo -type client -policy aap-demo
   ```

3. In AAP, create a credential type of kind *Cloud* with the inputs and
   injectors in `aap/nomad-credential-type.yml`, then a credential of that
   type holding the Nomad address, the token and the CA certificate. The
   injectors set `NOMAD_ADDR`, `NOMAD_TOKEN` and `NOMAD_CACERT`, which the
   collection reads as its
   [connection options](https://benemon.github.io/ansible-collection-nomad/branch/main/docsite/getting_started.html#connection-options).

4. Add this repository as a project.

5. Create an inventory with a source *Sourced from a Project* on
   `inventory/cluster.nomad.yml`, using the Nomad credential and the
   execution environment. Turn on *Update on launch*.

6. Create a job template for each playbook on that inventory, with the Nomad
   credential, the execution environment and *Prompt on launch* for
   variables.

## Running the playbooks

### Containers

Launch `deploy_container.yml` with:

```yaml
job_name: demo-nginx
container_image: docker.io/library/nginx:alpine
```

`container_port` (default `80`) and `instances` (default `1`) are optional.
Launch it again with another `job_name` for a second container. The play runs
on `localhost` against the Nomad API and reports the node and address of each
running allocation.

### Heartbeat worker

Launch `deploy_worker.yml`, then `verify_worker.yml`, with the same
`job_name` (default `heartbeat`). `deploy_worker.yml` also takes `node_pool`
(default `default`). The worker opens no ports and writes a counter to
`/local/heartbeat` every 5 seconds.

`verify_worker.yml` targets the inventory group `nomad_job_<job_name>`, so
the inventory must sync after the worker is deployed. *Update on launch*
does that. In each allocation it reads the heartbeat, then waits up to 30
seconds for the counter to advance.

The worker uses the exec driver because modules need Python inside the task,
and an exec task sees the client's `/usr/bin/python3` through its chroot.
Modules do not run in podman tasks. See
[what the task needs](https://benemon.github.io/ansible-collection-nomad/branch/main/docsite/exec.html#what-the-task-needs).

### Removing a job

Launch `remove_job.yml` with `job_name`. It stops the job, waits up to 300
seconds until no allocation is pending or running, then purges the job. A
job that does not exist is left alone and the play succeeds.
