# Commands on a workstation

## setup

### add the root

Copy your Root CA to the sources path

    sudo cp your-root-ca.pem /etc/pki/ca-trust/source/anchors/

Update the Root CA Trust Bundles

    sudo update-ca-trust

### Bootstrap step-cli

    tep ca bootstrap  --ca-url=ca.kingma:9000 --install --fingerprint <FINGERPRINT>

    
### Health

    step ca health

## create a ssl-cert

    step ca certificate npm.kingma npm.crt npm.key   --provisioner admin   --not-after 2160h


    
