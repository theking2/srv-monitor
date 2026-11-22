# step-ca: workstation commands

The CA runs on srv-monitor as a standalone container and listens on `https://ca.kingma:9000`. The commands below run on a workstation.

## Setup

### Bootstrap step-cli and trust the root

`--install` downloads the root certificate, verifies it against the fingerprint and installs it into the system trust store.

    step ca bootstrap --ca-url=https://ca.kingma:9000 --install --fingerprint <FINGERPRINT>

Alternative without step-cli: copy the root certificate into the trust store by hand.

Debian / Raspberry Pi OS:

    sudo cp your-root-ca.pem /usr/local/share/ca-certificates/kingma-root-ca.crt
    sudo update-ca-certificates

Fedora / RHEL:

    sudo cp your-root-ca.pem /etc/pki/ca-trust/source/anchors/
    sudo update-ca-trust

## Health

    step ca health

## Create a TLS certificate

    step ca certificate npm.kingma npm.crt npm.key --provisioner admin --not-after 2160h

2160h is 90 days. step-ca allows 24h by default, so the provisioner must permit the longer lifetime first. With remote provisioner management enabled:

    step ca provisioner update admin --x509-max-dur=2160h --x509-default-dur=2160h

Without remote management, set `maxTLSCertDuration` and `defaultTLSCertDuration` under `claims` of the provisioner in `ca.json` and restart the container.

Alternatively keep the 24h default and renew automatically:

    step ca renew --daemon npm.crt npm.key
