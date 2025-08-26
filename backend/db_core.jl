##configuracion base de datos
const DB_CONFIG = Dict(
    "host" => "10.10.10.100",  # Cambia por tu IP
    "port" => 3307,
    "database" => "MrSeq",
    "user" => "root",
    "password" => "Mistersecuencias88"
)


function get_db_connection()
return DBInterface.connect(
    MySQL.Connection,
    DB_CONFIG["host"],     # host
    DB_CONFIG["user"],     # usuario
    DB_CONFIG["password"]; # contraseña como tercer argumento posicional
    db   = DB_CONFIG["database"],
    port = DB_CONFIG["port"]
)
end

