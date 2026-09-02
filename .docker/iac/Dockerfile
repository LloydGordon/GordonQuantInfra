ARG TERRAFORM_VERSION=1.14.8
FROM hashicorp/terraform:${TERRAFORM_VERSION}

ARG TERRAGRUNT_VERSION=1.1.4
ARG TERRAGRUNT_SHA256=a2640da8455fa5f3671167e6373832b0907b9dc972dd01c2093cc7808934e158
ARG TFLINT_VERSION=0.64.0
ARG TFLINT_SHA256=cca9d13e2e1d7a2c627af60ff899a3c9b74212899416aeb96ec764d2ef954537

RUN apk add --no-cache bash curl git unzip \
    && curl -fsSLo /tmp/terragrunt \
      "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64" \
    && echo "${TERRAGRUNT_SHA256}  /tmp/terragrunt" | sha256sum -c - \
    && install -m 0755 /tmp/terragrunt /usr/local/bin/terragrunt \
    && curl -fsSLo /tmp/tflint.zip \
      "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    && echo "${TFLINT_SHA256}  /tmp/tflint.zip" | sha256sum -c - \
    && unzip /tmp/tflint.zip -d /tmp/tflint \
    && install -m 0755 /tmp/tflint/tflint /usr/local/bin/tflint \
    && rm -rf /tmp/terragrunt /tmp/tflint /tmp/tflint.zip

ENTRYPOINT []
WORKDIR /workspace

