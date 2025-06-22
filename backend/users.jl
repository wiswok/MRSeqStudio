function create_user(username::String, password::String, email::String)
    open(USERS_FILE, "a+") do file
        seek(file, 0)
        for ln in eachline(file)
            un, em = split(ln, " ")
            if username == un
                return HTTP.Response(
                    409, ["Content-Type" => "application/json"],
                    JSON3.write(Dict("error" => "Username already exists"))
                )
            end
            if email == em
                return HTTP.Response(
                    409, ["Content-Type" => "application/json"],
                    JSON3.write(Dict("error" => "Email already exists"))
                )
            end
        end
        println(file, "$username $email")
        open(AUTH_FILE, "a+") do f
            println(f, "$username $(bytes2hex(sha256(password)))")
        end
        println("Usuario añadido!")
        return HTTP.Response(201)
    end
end

function authenticate(username::String, password::String, ipaddr::String)
    open(AUTH_FILE, "a+") do file
        seek(file, 0)
        for ln in eachline(file)
            un, pass = split(ln, " ")
            if username == un && bytes2hex(sha256(password)) == pass # Valid credentials
                jwt1 = create_jwt(username, ipaddr, 1)
                jwt2 = create_jwt(username, ipaddr, 2)
                println("Autenticado! Tokens creados")
                expires = now() + Hour(12)
                expires_str = Dates.format(expires, dateformat"e, dd u yyyy HH:MM:SS") * " GMT"
                if !haskey(ACTIVE_SESSIONS, username) # Check if the user has already an active session
                    assign_process(username) # We assign a new julia process to the user
                else
                    println("ℹ️ Session already active for $username")
                end
                return HTTP.Response(
                    200, ["Set-Cookie" => "token=$(string(jwt1)); SameSite=Lax; Expires=$(expires_str)"],
                    JSON3.write(Dict("token" => string(jwt2), "username" => username))
                )
            end
        end # Invalid credentials
        println("❌ Invalid credentials")
        return HTTP.Response(401)
    end
end

function create_jwt(username, ipaddr, keyidx) 
    iat = round(Int, datetime2unix(now()))
    exp = iat + 12 * 60 * 60  # 12 hours in seconds

    payload = Dict{String, Any}(
        "iss" => "seqPlayground",
        "iat" => "$iat",
        "exp" => "$exp",
        "username" => username,
        "userip" => ipaddr,
    )

    jwt = JWT(; payload=payload)

    keyset_url = "$(@__DIR__)/keys/jwkkey.json"

    keyset = JWKSet("file://$keyset_url");
    refresh!(keyset)

    signingkeyset = deepcopy(keyset)
    keyids = String[]
    for k in keys(signingkeyset.keys)
        push!(keyids, k)
        signingkeyset.keys[k] = JWKRSA(signingkeyset.keys[k].kind, MbedTLS.parse_keyfile(joinpath(dirname(keyset_url), "$k.private.pem")))
    end

    keyid = keyids[keyidx]
    sign!(jwt, signingkeyset, keyid)

    return jwt
end

function get_jwt_from_cookie(cookie)
    if cookie === nothing || cookie == ""
        return nothing
    end
    # cookie es tipo String, ej: "token=abc123; other=foo"
    cookies = split(cookie, "; ")
    for c in cookies
        if startswith(c, "token=")
            return JWT(; jwt=string(split(c, "=")[2]))
        end
    end
    return nothing
end

function get_jwt_from_auth_header(auth_header)
    if auth_header === nothing || auth_header == ""
        println("→ No Authorization header found")
        return nothing
    end
    parts = split(auth_header)
    if length(parts) != 2 || lowercase(parts[1]) != "bearer"
        println("→ Authorization header format incorrect, redirecting")
        return nothing
    end
    return JWT(; jwt=string(parts[2]))
end

function check_jwt(jwt, ipaddr, keyidx)
    if jwt === nothing
        return false
    end

    keyset_url = "$(@__DIR__)/keys/jwkkey.json"

    keyset = JWKSet("file://$keyset_url");
    refresh!(keyset)

    signingkeyset = deepcopy(keyset)
    keyids = String[]
    for k in keys(signingkeyset.keys)
        push!(keyids, k)
        signingkeyset.keys[k] = JWKRSA(signingkeyset.keys[k].kind, MbedTLS.parse_keyfile(joinpath(dirname(keyset_url), "$k.private.pem")))
    end

    keyid = keyids[keyidx]

    # println("keyid: ", keyid)

    validate!(jwt, keyset, keyid)
    
    if isvalid(jwt) 
        # & (ipaddr === claims(jwt)["userip"])
        println("✅ Valid JWT $(keyidx)")
        return true
    else
        println("❌ Invalid or expired JWT $(keyidx)")
        # return HTTP.Response(303, ["Location" => "/login"])
        return false
    end
end

function assign_process(username)
    if !haskey(ACTIVE_SESSIONS, username)
        pid = get_least_used_pid()
        ACTIVE_SESSIONS[username] = pid
    else    
        println("ℹ️ Session already active for $username")
    end
end

function get_least_used_pid()
    pid_counts = Dict{Int, Int}()
    for pid in values(ACTIVE_SESSIONS)
        pid_counts[pid] = get(pid_counts, pid, 0) + 1
    end
    return argmin(pid -> get(pid_counts, pid, 0), workers())
end