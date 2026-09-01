module KubeManifestFixtures
  VALID_SINGLE_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: my-app
    YML

  MISSING_API_VERSION_DOC = <<-YML
    kind: Deployment
    metadata:
      name: my-app
    YML

  MISSING_METADATA_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    YML

  MISSING_KIND_DOC = <<-YML
    apiVersion: apps/v1
    metadata:
      name: orphan
    YML

  MISSING_NAME_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      namespace: default
    YML

  NULL_NAME_DOC = <<-YML
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name:
    YML

  MALFORMED_YAML = <<-YML
    key: [unclosed bracket
    YML
end
