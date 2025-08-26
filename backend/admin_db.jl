"""
get_all_users()

Obtener todos los usuarios del sistema con sus privilegios.

# Returns
- `HTTP.Response`: Lista de usuarios en formato JSON
"""

function get_all_users()
    conn = get_db_connection()
    try
        # Consulta con JOIN para obtener usuarios con todos sus privilegios
        query = """
        SELECT u.id, u.username, u.email, u.password_hash, u.is_premium, u.is_admin, u.created_at, u.updated_at,
            p.storage_quota_mb, p.gpu_access, p.max_daily_sequences
        FROM users u
        LEFT JOIN user_privileges p ON u.id = p.user_id
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        users = []
        for row in result
            # Crear objeto de usuario con todos sus privilegios
            user = Dict(
                "id" => row[1],
                "username" => row[2],
                "email" => row[3],
                "is_premium" => row[5] == 1,
                "is_admin" => row[6] == 1,
                "created_at" => string(row[7]),
                "updated_at" => string(row[8]),
                "storage_quota_mb" => row[9] === nothing ? 0.5 : row[9],
                "gpu_access" => row[10] === nothing ? false : row[10] == 1,
                "max_daily_sequences" => row[11] === nothing ? 10 : row[11]
            )
            push!(users, user)
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(users))
    catch e
        println("❌ Error fetching users: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_user_sequence_usage(user_id)

Obtiene el uso de secuencias para un usuario específico.

# Returns
- `HTTP.Response`: Datos de uso en formato JSON
"""
function get_user_sequence_usage(user_id)
    conn = get_db_connection()
    try
        query = """
        SELECT date, sequences_used 
        FROM daily_sequence_usage 
        WHERE user_id = ?
        ORDER BY date DESC
        LIMIT 30
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [user_id])
        
        usage_data = []
        for row in result
            entry = Dict(
                "date" => string(row[1]),
                "sequences_used" => row[2]
            )
            push!(usage_data, entry)
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(usage_data))
    catch e
        println("❌ Error fetching sequence usage: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
admin_create_user(user_data)

Crear un nuevo usuario desde el panel de administrador.

# Arguments
- `user_data::Dict`: Datos del nuevo usuario

# Returns
- `HTTP.Response`: Código de respuesta HTTP
"""


function admin_create_user(user_data::Dict)
    # Acceder a los datos usando exclusivamente strings
    username = user_data["username"]
    password = user_data["password"]
    email = user_data["email"]
    is_premium = get(user_data, "is_premium", false)
    is_admin = get(user_data, "is_admin", false)
    storage_quota_mb = get(user_data, "storage_quota_mb", 0.5)
    gpu_access = get(user_data, "gpu_access", false)
    max_daily_sequences = get(user_data, "max_daily_sequences", 10)
    
    conn = get_db_connection()
    try
        # Verificar si usuario/email existen
        stmt = DBInterface.prepare(conn, "SELECT username, email FROM users WHERE username = ? OR email = ?")
        result = DBInterface.execute(stmt, [username, email])
        
        for row in result
            if row[1] == username
                return HTTP.Response(409, ["Content-Type" => "application/json"],
                    JSON3.write(Dict("error" => "El nombre de usuario ya existe")))
            end
            if row[2] == email
                return HTTP.Response(409, ["Content-Type" => "application/json"],
                    JSON3.write(Dict("error" => "El email ya existe")))
            end
        end
        
        # Insertar nuevo usuario
        password_hash = bytes2hex(sha256(password))
        stmt = DBInterface.prepare(conn, """
            INSERT INTO users (username, email, password_hash, is_premium, is_admin, created_at, updated_at) 
            VALUES (?, ?, ?, ?, ?, NOW(), NOW())
        """)
        DBInterface.execute(stmt, [username, email, password_hash, is_premium ? 1 : 0, is_admin ? 1 : 0])
        
        # Método alternativo: Obtener el ID con una consulta
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE username = ?")
        result = DBInterface.execute(stmt, [username])
        user_id = 0
        for row in result
            user_id = row[1]
            break
        end
        
        # Configurar privilegios de almacenamiento incluyendo los nuevos campos
        stmt = DBInterface.prepare(conn, """
            INSERT INTO user_privileges (user_id, storage_quota_mb, gpu_access, max_daily_sequences) 
            VALUES (?, ?, ?, ?)
        """)
        DBInterface.execute(stmt, [user_id, storage_quota_mb, gpu_access ? 1 : 0, max_daily_sequences])
        
        println("✅ Usuario añadido por admin: $username (Premium: $is_premium, Admin: $is_admin)")
        return HTTP.Response(201)
        
    catch e
        println("❌ Error creating user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor: $e")))
    finally
        DBInterface.close!(conn)
    end
end

"""
update_user(id, user_data)

Actualizar datos de un usuario desde el panel de administrador.

# Arguments
- `id::Int`: ID del usuario a actualizar
- `user_data::Dict`: Datos a actualizar

# Returns
- `HTTP.Response`: Código de respuesta HTTP
"""
# Modificar la función para usar exclusivamente strings

function update_user(id::Int, user_data::Dict)
    conn = get_db_connection()
    try
        # Verificar que el usuario existe
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE id = ?")
        result = DBInterface.execute(stmt, [id])
        found = false
        for row in result
            found = true
            break
        end
        
        if !found
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Usuario no encontrado")))
        end
        
        # Actualizar tabla users - usar siempre strings para acceder
        updates = String[]
        params = []
        
        if haskey(user_data, "email")
            push!(updates, "email = ?")
            push!(params, user_data["email"])
        end
        
        if haskey(user_data, "is_premium")
            push!(updates, "is_premium = ?")
            push!(params, user_data["is_premium"] ? 1 : 0)
        end
        
        if haskey(user_data, "is_admin")
            push!(updates, "is_admin = ?")
            push!(params, user_data["is_admin"] ? 1 : 0)
        end
        
        if haskey(user_data, "password")
            push!(updates, "password_hash = ?")
            push!(params, bytes2hex(sha256(user_data["password"])))
        end
        
        # Añadir timestamp de actualización
        push!(updates, "updated_at = NOW()")
        
        if length(updates) > 0
            update_query = "UPDATE users SET " * join(updates, ", ") * " WHERE id = ?"
            push!(params, id)
            stmt = DBInterface.prepare(conn, update_query)
            DBInterface.execute(stmt, params)
        end
        
        # Verificar si ya existen privilegios para este usuario
        stmt = DBInterface.prepare(conn, "SELECT user_id FROM user_privileges WHERE user_id = ?")
        result = DBInterface.execute(stmt, [id])
        
        privileges_exist = false
        for row in result
            privileges_exist = true
            break
        end
        
        # Actualizar privilegios
        privilege_updates = []
        privilege_params = []
        
        if haskey(user_data, "storage_quota_mb")
            push!(privilege_updates, "storage_quota_mb = ?")
            push!(privilege_params, user_data["storage_quota_mb"])
        end
        
        if haskey(user_data, "gpu_access")
            push!(privilege_updates, "gpu_access = ?")
            push!(privilege_params, user_data["gpu_access"] ? 1 : 0)
        end
        
        if haskey(user_data, "max_daily_sequences")
            push!(privilege_updates, "max_daily_sequences = ?")
            push!(privilege_params, user_data["max_daily_sequences"])
        end
        
        if length(privilege_updates) > 0
            if privileges_exist
                # Actualizar privilegios existentes
                privilege_query = "UPDATE user_privileges SET " * join(privilege_updates, ", ") * " WHERE user_id = ?"
                push!(privilege_params, id)
                stmt = DBInterface.prepare(conn, privilege_query)
                DBInterface.execute(stmt, privilege_params)
            else
                # Crear nuevos privilegios con valores predeterminados para campos no especificados
                default_storage = haskey(user_data, "storage_quota_mb") ? user_data["storage_quota_mb"] : 0.5
                default_gpu = haskey(user_data, "gpu_access") ? (user_data["gpu_access"] ? 1 : 0) : 0
                default_max_seq = haskey(user_data, "max_daily_sequences") ? user_data["max_daily_sequences"] : 10
                
                stmt = DBInterface.prepare(conn, "INSERT INTO user_privileges (user_id, storage_quota_mb, gpu_access, max_daily_sequences) VALUES (?, ?, ?, ?)")
                DBInterface.execute(stmt, [id, default_storage, default_gpu, default_max_seq])
            end
        end
        
        println("✅ Usuario actualizado: ID $id")
        return HTTP.Response(200)
        
    catch e
        println("❌ Error updating user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor: $e")))
    finally
        DBInterface.close!(conn)
    end
end

"""
delete_user(id)

Eliminar un usuario del sistema.

# Arguments
- `id::Int`: ID del usuario a eliminar

# Returns
- `HTTP.Response`: Código de respuesta HTTP
"""
function delete_user(id::Int)
    conn = get_db_connection()
    try
        # Verificar que el usuario existe y no es administrador
        stmt = DBInterface.prepare(conn, "SELECT username, is_admin FROM users WHERE id = ?")
        result = DBInterface.execute(stmt, [id])
        
        username = nothing
        is_admin_user = false
        
        for row in result
            username = row[1]
            is_admin_user = row[2] == 1
            break
        end
        
        if username === nothing
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Usuario no encontrado")))
        end
        
        if is_admin_user
            return HTTP.Response(403, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "No se puede eliminar una cuenta de administrador")))
        end
        
        # Eliminar usuario y sus datos relacionados
        DBInterface.execute(conn, "START TRANSACTION")
        
        # Eliminar privilegios
        stmt = DBInterface.prepare(conn, "DELETE FROM user_privileges WHERE user_id = ?")
        DBInterface.execute(stmt, [id])
        
        # Eliminar uso de secuencias
        stmt = DBInterface.prepare(conn, "DELETE FROM daily_sequence_usage WHERE user_id = ?")
        DBInterface.execute(stmt, [id])
        
        # Eliminar resultados
        stmt = DBInterface.prepare(conn, "DELETE FROM results WHERE user_id = ?")
        DBInterface.execute(stmt, [id])
        
        # Finalmente eliminar el usuario
        stmt = DBInterface.prepare(conn, "DELETE FROM users WHERE id = ?")
        DBInterface.execute(stmt, [id])
        
        DBInterface.execute(conn, "COMMIT")
        
        # Eliminar sesión si está activa
        if haskey(ACTIVE_SESSIONS, username)
            delete!(ACTIVE_SESSIONS, username)
        end
        
        println("✅ Usuario eliminado: $username (ID: $id)")
        return HTTP.Response(200)
        
    catch e
        DBInterface.execute(conn, "ROLLBACK")
        println("❌ Error deleting user: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_sequence_usage_stats()

Obtiene estadísticas de uso de secuencias para todos los usuarios.

# Returns
- `HTTP.Response`: Estadísticas en formato JSON
"""
function get_sequence_usage_stats()
    conn = get_db_connection()
    try
        # Consulta para obtener estadísticas diarias agregadas
        daily_query = """
        SELECT date, SUM(sequences_used) as total_sequences
        FROM daily_sequence_usage
        GROUP BY date
        ORDER BY date DESC
        LIMIT 30
        """
        
        # Consulta para obtener top usuarios
        user_query = """
        SELECT u.username, SUM(d.sequences_used) as total_sequences
        FROM daily_sequence_usage d
        JOIN users u ON d.user_id = u.id
        WHERE d.date >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
        GROUP BY d.user_id
        ORDER BY total_sequences DESC
        LIMIT 10
        """
        
        # Ejecutar consultas
        stmt1 = DBInterface.prepare(conn, daily_query)
        daily_result = DBInterface.execute(stmt1)
        
        stmt2 = DBInterface.prepare(conn, user_query)
        user_result = DBInterface.execute(stmt2)
        
        # Procesar resultados
        daily_stats = []
        for row in daily_result
            push!(daily_stats, Dict(
                "date" => string(row[1]),
                "total_sequences" => row[2]
            ))
        end
        
        user_stats = []
        for row in user_result
            push!(user_stats, Dict(
                "username" => row[1],
                "total_sequences" => row[2]
            ))
        end
        
        # Construir respuesta
        response = Dict(
            "daily_stats" => daily_stats,
            "top_users" => user_stats
        )
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(response))
    catch e
        println("❌ Error fetching sequence usage stats: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
reset_user_password(id, new_password)

Cambia la contraseña de un usuario (operación de administrador).

# Arguments
- `id::Int`: ID del usuario
- `new_password::String`: Nueva contraseña

# Returns
- `HTTP.Response`: Código de respuesta HTTP
"""
function reset_user_password(id::Int, new_password::String)
    conn = get_db_connection()
    try
        # Verificar que el usuario existe
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE id = ?")
        result = DBInterface.execute(stmt, [id])
        
        found = false
        for row in result
            found = true
            break
        end
        
        if !found
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Usuario no encontrado")))
        end
        
        # Actualizar contraseña
        password_hash = bytes2hex(sha256(new_password))
        stmt = DBInterface.prepare(conn, "UPDATE users SET password_hash = ?, updated_at = NOW() WHERE id = ?")
        DBInterface.execute(stmt, [password_hash, id])
        
        println("✅ Contraseña reseteada para usuario ID: $id")
        return HTTP.Response(200)
        
    catch e
        println("❌ Error resetting password: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end
"""
get_all_sequences()

Obtiene todas las secuencias registradas.

# Returns
- `HTTP.Response`: Lista de secuencias en formato JSON
"""
function get_all_sequences()
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        ORDER BY r.created_at DESC
        LIMIT 1000
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        sequences = []
        for row in result
            push!(sequences, Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "created_at" => string(row[5])
            ))
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(sequences))
    catch e
        println("❌ Error obteniendo secuencias: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_user_sequences(user_id)

Obtiene las secuencias registradas para un usuario específico.

# Returns
- `HTTP.Response`: Lista de secuencias del usuario en formato JSON
"""
function get_user_sequences(user_id::Int)
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        WHERE r.user_id = ?
        ORDER BY r.created_at DESC
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [user_id])
        
        sequences = []
        for row in result
            push!(sequences, Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "created_at" => string(row[5])
            ))
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(sequences))
    catch e
        println("❌ Error obteniendo secuencias del usuario: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_result_details(result_id)

Obtiene los detalles de un resultado específico.

# Returns
- `HTTP.Response`: Detalles del resultado en formato JSON
"""
function get_result_details(result_id::Int)
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.file_path, 
            r.file_size_mb, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        WHERE r.id = ?
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [result_id])
        
        for row in result
            result_data = Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "file_path" => row[5],
                "file_size_mb" => row[6],
                "created_at" => string(row[7])
            )
            
            # Verificar si el archivo existe
            if isfile(row[5])
                result_data["file_exists"] = true
            else
                result_data["file_exists"] = false
            end
            
            return HTTP.Response(200, ["Content-Type" => "application/json"],
                JSON3.write(result_data))
        end
        
        return HTTP.Response(404, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Resultado no encontrado")))
    catch e
        println("❌ Error obteniendo detalles del resultado: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
delete_result(result_id)

Elimina un resultado y su archivo asociado.

# Returns
- `HTTP.Response`: Confirmación de la eliminación
"""
function delete_result(result_id::Int, req)
    # Obtener usuario y privilegios desde el JWT
    is_admin, username = check_admin(req)
    if username === nothing
        return HTTP.Response(401, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "No autenticado")))
    end

    conn = get_db_connection()
    try
        # Obtener información del resultado
        query = "SELECT user_id, file_path FROM results WHERE id = ?"
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [result_id])
        
        owner_id = nothing
        file_path = nothing
        for row in result
            owner_id = row[1]
            file_path = row[2]
            break
        end
        
        if owner_id === nothing
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Resultado no encontrado")))
        end

        # Obtener el id del usuario que solicita el borrado
        stmt = DBInterface.prepare(conn, "SELECT id FROM users WHERE username = ?")
        user_result = DBInterface.execute(stmt, [username])
        user_id = nothing
        for row in user_result
            user_id = row[1]
            break
        end

        # Solo puede borrar si es el propietario o admin
        if user_id != owner_id && !is_admin
            return HTTP.Response(403, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "No tienes permiso para borrar este resultado")))
        end
        
        # Eliminar archivo si existe
        if isfile(file_path)
            try
                rm(file_path)
            catch e
                println("⚠️ No se pudo eliminar el archivo: $file_path. Error: $e")
            end
        end
        
        # Eliminar registro de la base de datos
        stmt = DBInterface.prepare(conn, "DELETE FROM results WHERE id = ?")
        DBInterface.execute(stmt, [result_id])
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(Dict("message" => "Resultado eliminado correctamente")))
    catch e
        println("❌ Error eliminando resultado: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_all_sequence_usage()

Obtiene todas las secuencias registradas.

# Returns
- `HTTP.Response`: Lista de uso de secuencias en formato JSON
"""
function get_all_sequence_usage()
    conn = get_db_connection()
    try
        query = """
        SELECT d.id, d.user_id, u.username, d.date, d.sequences_used
        FROM daily_sequence_usage d
        JOIN users u ON d.user_id = u.id
        ORDER BY d.date DESC
        LIMIT 1000
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        usage_data = []
        for row in result
            push!(usage_data, Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "date" => string(row[4]),
                "sequences_used" => row[5]
            ))
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(usage_data))
    catch e
        println("❌ Error obteniendo datos de uso: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
get_sequence_usage_by_id(usage_id)

Obtiene un registro específico de uso de secuencias.

# Returns
- `HTTP.Response`: Datos del registro en formato JSON
"""
function get_sequence_usage_by_id(usage_id::Int)
    conn = get_db_connection()
    try
        query = """
        SELECT d.id, d.user_id, u.username, d.date, d.sequences_used
        FROM daily_sequence_usage d
        JOIN users u ON d.user_id = u.id
        WHERE d.id = ?
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt, [usage_id])
        
        for row in result
            usage_data = Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "date" => string(row[4]),
                "sequences_used" => row[5]
            )
            
            return HTTP.Response(200, ["Content-Type" => "application/json"],
                JSON3.write(usage_data))
        end
        
        return HTTP.Response(404, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Registro no encontrado")))
    catch e
        println("❌ Error obteniendo registro de uso: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end

"""
update_sequence_usage(usage_id, sequences_used)

Actualiza el número de secuencias usadas en un registro.

# Returns
- `HTTP.Response`: Respuesta HTTP
"""
function update_sequence_usage(usage_id::Int, sequences_used::Int)
    conn = get_db_connection()
    try
        # Verificar si el registro existe
        stmt = DBInterface.prepare(conn, "SELECT id FROM daily_sequence_usage WHERE id = ?")
        result = DBInterface.execute(stmt, [usage_id])
        
        found = false
        for row in result
            found = true
            break
        end
        
        if !found
            return HTTP.Response(404, ["Content-Type" => "application/json"],
                JSON3.write(Dict("error" => "Registro no encontrado")))
        end
        
        # Actualizar registro
        stmt = DBInterface.prepare(conn, "UPDATE daily_sequence_usage SET sequences_used = ? WHERE id = ?")
        DBInterface.execute(stmt, [sequences_used, usage_id])
        
        return HTTP.Response(200)
    catch e
        println("❌ Error actualizando uso de secuencia: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end
"""
get_all_results()

Obtiene todos los resultados de simulaciones registrados.

# Returns
- `HTTP.Response`: Lista de resultados en formato JSON
"""
function get_all_results()
    conn = get_db_connection()
    try
        query = """
        SELECT r.id, r.user_id, u.username, r.sequence_id, r.file_path, 
            r.file_size_mb, r.created_at
        FROM results r
        JOIN users u ON r.user_id = u.id
        ORDER BY r.created_at DESC
        LIMIT 1000
        """
        
        stmt = DBInterface.prepare(conn, query)
        result = DBInterface.execute(stmt)
        
        results_data = []
        for row in result
            result_item = Dict(
                "id" => row[1],
                "user_id" => row[2],
                "username" => row[3],
                "sequence_id" => row[4],
                "file_path" => row[5],
                "file_size_mb" => row[6],
                "created_at" => string(row[7]),
                "file_exists" => isfile(row[5])
            )
            push!(results_data, result_item)
        end
        
        return HTTP.Response(200, ["Content-Type" => "application/json"],
            JSON3.write(results_data))
    catch e
        println("❌ Error obteniendo resultados: ", e)
        return HTTP.Response(500, ["Content-Type" => "application/json"],
            JSON3.write(Dict("error" => "Error interno del servidor")))
    finally
        DBInterface.close!(conn)
    end
end


