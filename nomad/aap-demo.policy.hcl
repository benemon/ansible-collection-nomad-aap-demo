namespace "default" {
  capabilities = ["submit-job", "read-job", "list-jobs"]
}

node {
  policy = "read"
}
