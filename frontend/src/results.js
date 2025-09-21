function showMsg(text, error = true) {
    const msg = document.getElementById("msg");
    msg.textContent = text;
    msg.style.display = "block";
    msg.style.color = error ? "#d32f2f" : "#388E3C";
    setTimeout(() => { msg.style.display = "none"; }, 3000);
}

function loadUserResults() {
    fetch("/api/results", { 
        headers: {
            "Authorization": "Bearer " + localStorage.token
        }
    })
    .then(res => {
        if (!res.ok) throw new Error("No se pudieron cargar los resultados");
        return res.json();
    })
    .then(results => {
        const panel = document.getElementById("resultsPanel");
        panel.innerHTML = "";
        if (results.length === 0) {
            panel.innerHTML = "<p>No tienes resultados guardados.</p>";
            return;
        }
        results.forEach(result => {
            const row = document.createElement("div");
            row.className = "result-row";
            row.innerHTML = `
                <span>
                    <span class="result-name">ID: ${result.id}</span>
                    <span class="result-seq">Secuencia: ${result.sequence_id}</span>
                    <span class="result-date">${result.created_at}</span>
                </span>
                <span>
                    <button class="btn" onclick="downloadResult(${result.id})">Descargar</button>
                    <button class="btn" onclick="deleteResult(${result.id})">Eliminar</button>
                </span>
            `;
            panel.appendChild(row);
        });
    })
    .catch(err => {
        showMsg(err.message);
        document.getElementById("resultsPanel").innerHTML = "<p>Error al cargar resultados.</p>";
    });
}

function downloadResult(id) {
    window.location.href = `/api/results/${id}/download`;
}

function deleteResult(id) {
    if (!confirm("¿Seguro que quieres eliminar este resultado?")) return;
    fetch(`/api/results/${id}`, {
        method: "DELETE",
        headers: {
            "Authorization": "Bearer " + localStorage.token
        }
    })
    .then(res => {
        if (res.ok) {
            showMsg("Resultado eliminado correctamente", false);
            loadUserResults();
        } else {
            res.json().then(data => showMsg(data.error || "No se pudo eliminar el resultado"));
        }
    })
    .catch(() => showMsg("Error al eliminar el resultado"));
}

document.addEventListener("DOMContentLoaded", loadUserResults);
/// modificar los archivos de users_core etc en la maquiina virtual y actualziar el js tambien

