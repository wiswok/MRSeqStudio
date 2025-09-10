function komaMRIsim(phantom, seq_json, scanner_json){

    const scannerObj = JSON.parse(scanner_json);
    const seqObj     = JSON.parse(seq_json);

    var params = {
        phantom: phantom,
        sequence: seqObj,
        scanner: scannerObj
    }

    document.getElementById('simResult').style.visibility  = "hidden";

    clearSimulationPanel();

    // HTTP Status Codes:
    // 200: OK
    // 202: Accepted
    // 303: See other

    fetch("/simulate",{
        method: "POST",
        headers:{
            "Content-type": "application/json",
            "Authorization": "Bearer " + localStorage.token,
        },
        body: JSON.stringify(params)})
    .then(res => {
            if ((res.status == 202) && (loc = res.headers.get('location'))){
                requestResult(loc)
            }else{
                // Error
            }
        }
    )
}

function clearSimulationPanel() {
    document.getElementById("simProgress").style.visibility = "collapse";
    document.getElementById('response').style.visibility    = "collapse";
    document.getElementById('myProgress').style.visibility  = "collapse";
    document.getElementById("myBar").style.width            = "0%";
    document.getElementById("simErrorMsg").innerHTML          = "";
    document.getElementById('loading-sim').style.display    = "none";
}

function requestResult(loc){
    fetch(loc + "?" + new URLSearchParams({
            width:  document.getElementById("simResult").offsetWidth,
            height: document.getElementById("simResult").offsetHeight
        }).toString(), {
            method: "GET",
            headers:{
                "Authorization": "Bearer " + localStorage.token,
            },
        })
    .then(res => {
        if (res.redirected) {
            // Caso en que se recibe un 303 (redirect)
            document.getElementById("simProgress").style.visibility = "visible";
            document.getElementById('response').style.visibility    = "visible";
            document.getElementById('loading-sim').style.display    = "block";
            
            return res.json().then(json => {
                if (json === -1) {
                    document.getElementById('response').innerHTML = "Starting simulation...";
                } else if (json === -2){
                    //Error
                    setTimeout(function() { requestResult(loc); }, 500);
                } else {
                    // Status Bar 
                    document.getElementById('response').innerHTML = json + "%";
                    document.getElementById('myProgress').style.visibility = "visible";
                    var elem = document.getElementById("myBar");
                    elem.style.width = json + "%";
                }
                if (json > -2 && json < 100) {
                    setTimeout(function() { requestResult(loc); }, 500);
                } else if (json === 100) {
                    document.getElementById('response').innerHTML = "Reconstructing...";
                    document.getElementById('myProgress').style.visibility = "collapse";
                    setTimeout(function() { requestResult(loc); }, 500);
                } 
            }).then(() => { return; });  // 🔹 IMPORTANTE: Evita que el flujo siga al siguiente .then()
        } if (res.ok) {
            clearSimulationPanel();
            return res.text();
        } if (res.status == 500) {
            clearSimulationPanel();
            return res.json().then(json => {
                document.getElementById("simErrorMsg").textContent = 
                    "Simulation failed in KomaMRI: the provided sequence could not be simulated or reconstructed.\nDetails:\n" + json.msg;
            }).then(() => { return; });
        } throw new Error('Request error');
    })
    .then(html => {
        if (!html) return;
        var iframe = document.getElementById("simResult")
        iframe.srcdoc = html;
        iframe.onload = function() {
            document.getElementById('loading-sim').style.display = "none";
            iframe.style.visibility = "visible";
        };
    })
    .catch(error => {
        console.error("Error in the request:", error);
    });   
}

function plot_seq(scanner_json, seq_json){
    const scannerObj = JSON.parse(scanner_json);
    const seqObj     = JSON.parse(seq_json);

    // Combina los dos objetos en uno solo
    const combinedObj = {
        scanner: scannerObj,
        sequence: seqObj,
        height: document.getElementById("seq-diagram").offsetHeight,
        width: document.getElementById("seq-diagram").offsetWidth,
    };

    const iframe = document.getElementById("seq-diagram");
    const errorBox = document.getElementById("seqErrorMsg");

    iframe.style.visibility = "hidden";
    document.getElementById("loading-seq").style.display = "block";   

    // Crear listener temporal
    const onIframeLoad = () => {
        iframe.style.visibility = "visible";
        iframe.removeEventListener("load", onIframeLoad);  // Evita múltiples disparos
    };

    iframe.addEventListener("load", onIframeLoad);

    fetch("/plot_sequence", {
        method: "POST",
        headers: {
            "Content-type": "application/json",
            "Authorization": "Bearer " + localStorage.token,
        },
        body: JSON.stringify(combinedObj)
    })
    .then(res => {
        document.getElementById("loading-seq").style.display = "none";

        if (res.ok) {
            return res.text();
        } else {
            return res.json().then(json => {
                throw new Error(json.msg);
            });
        }
    })
    .then(html => {
        iframe.srcdoc = html;
        errorBox.textContent = "";
    })
    .catch(error => {
        iframe.style.visibility = "hidden";
        errorBox.textContent = 
            "Failed to plot sequence: the provided sequence could not be plotted.\nDetails:\n" + error.message;
    });
}

function logout() {
    fetch('/logout')
        .then(res => {
            if (res.status == 200) {
                console.log("Esto va bien?");
                localStorage.clear();
                setTimeout(() => {location.href = "/login";}, 0);
            }
        });
}

function loadUser() {
    const userText = document.getElementById("user-menu-text");
    userText.innerHTML = "Hi, " + localStorage.username;
}