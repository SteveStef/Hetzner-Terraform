# MinIO Client Setup - Linux

## 1. Install MinIO Client
```bash
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/
mc --version
```

## 2. Install Cloudflare Origin CA Certificate
```bash
curl -o cloudflare-origin-ca.pem https://developers.cloudflare.com/ssl/static/origin_ca_rsa_root.pem
sudo cp cloudflare-origin-ca.pem /usr/local/share/ca-certificates/cloudflare-origin-ca.crt
sudo update-ca-certificates
```

## 3. Create Alias
```bash
# HTTPS (recommended after installing certificate)
mc alias set myminio https://storage.example.com ACCESS_KEY SECRET_KEY

# Or with --insecure if certificate issues persist
mc alias set myminio https://storage.example.com ACCESS_KEY SECRET_KEY --insecure
```

## 4. Basic Commands
```bash
# List aliases
mc alias list

# List buckets
mc ls myminio

# Create bucket
mc mb myminio/bucket-name

# Upload file
mc cp /path/file.txt myminio/bucket-name/

# Download file
mc cp myminio/bucket-name/file.txt /local/path/
```
