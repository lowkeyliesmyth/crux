module KubeManifestFixtures
  BACKSLASH_NAME_DOC = <<-YML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: "foo\\\\bar"
    YML

  CONFIGMAP_MULTILINE_DOC = <<-'YML'
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: shield-cluster
    data:
      cluster-shield.yaml: "cluster_config:\n  name: foo\n"
    YML

  LEADING_DOT_NAME_DOC = <<-YML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: .hidden
    YML

  MALFORMED_YAML = <<-YML
    key: [unclosed bracket
    YML

  MISSING_API_VERSION_DOC = <<-YML
    kind: Deployment
    metadata:
      name: my-app
    YML

  MISSING_KIND_DOC = <<-YML
    apiVersion: apps/v1
    metadata:
      name: orphan
    YML

  MISSING_METADATA_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    YML

  MISSING_NAME_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      namespace: default
    YML

  MIXED_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: my-app
    ---
    apiVersion: v1
    metadata:
      name: my-app
    YML

  NULL_UNI_NAME_DOC = <<-'YML'
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: "foo\u0000bar"
    YML

  NULL_NAME_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name:
    YML

  SLASH_NAME_DOC = <<-YML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: foo/bar
    YML

  TRAVERSAL_NAME_DOC = <<-YML
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: ../../../tmp/pwned
    YML

  VALID_MULTI_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: my-app
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: my-app
    YML

  VALID_SINGLE_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: my-app
    YML
end
