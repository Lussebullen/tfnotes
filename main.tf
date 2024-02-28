variable secretConfig {
  type = map(any)
  sensitive = true
}

variable publicConfig {
  type = map(any)
  sensitive = false
}
