#!/bin/bash

echo "🔑 Generando múltiples claves JWT..."

# Generar primera clave
./genkey.sh jwkkey1

# Generar segunda clave  
./genkey.sh jwkkey2

# Crear JWK con múltiples claves
python3 << 'EOF'
import json
import base64
from cryptography.hazmat.primitives import serialization

def pem_to_jwk_entry(private_pem_path, kid):
    with open(private_pem_path, 'rb') as f:
        private_key = serialization.load_pem_private_key(f.read(), password=None)
    
    private_numbers = private_key.private_numbers()
    public_numbers = private_numbers.public_numbers
    
    def int_to_base64url(value):
        byte_length = (value.bit_length() + 7) // 8
        return base64.urlsafe_b64encode(value.to_bytes(byte_length, 'big')).decode('ascii').rstrip('=')
    
    return {
        "kty": "RSA",
        "kid": kid,
        "use": "sig", 
        "alg": "RS256",
        "n": int_to_base64url(public_numbers.n),
        "e": int_to_base64url(public_numbers.e)
    }

# Crear JWK con múltiples claves
jwk = {
    "keys": [
        pem_to_jwk_entry("jwkkey1.private.pem", "jwkkey1"),
        pem_to_jwk_entry("jwkkey2.private.pem", "jwkkey2")
    ]
}

with open('jwkkey.json', 'w') as f:
    json.dump(jwk, f, indent=2)

print("✅ Múltiples claves JWT generadas")
EOF

echo "🎉 Configuración completada"
ls -la jwkkey*
