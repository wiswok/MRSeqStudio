These `.pem` keys were created with:

```bash
openssl genrsa -out ${1}.private.pem 2048
openssl rsa -in ${1}.private.pem -outform PEM -pubout -out ${1}.public.pem
openssl rsa -pubin -in ${1}.public.pem -modulus -noout
openssl rsa -pubin -in ${1}.public.pem -text -noout
```

and then exported to JWK with [this web utility](https://irrte.ch/jwt-js-decode/pem2jwk.html).