namespace "default" {
  capabilities = ["submit-job", "read-job", "list-jobs", "alloc-exec"]
}

node {
  policy = "read"
}
