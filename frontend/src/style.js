
// ---------------------- Mobile tabs handling ----------------------------
function openScreen(screenId) {
    // Oculta todos los divs
    var tabs = document.getElementsByClassName("box");
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].style.display = "none";
    }
  
    // Muestra el div seleccionado
    document.getElementById(screenId).style.display = "block";

    // Elimina la clase 'tab-active' de todos los botones
    var buttons = document.querySelectorAll(".tabs-mobile button");
    for (var i = 0; i < buttons.length; i++) {
        buttons[i].classList.remove("tab-active");
    }
    // Agrega la clase 'tab-active' al botón/tab activo
    document.getElementById("btn-" + screenId).classList.add("tab-active");
}

// Función para manejar el cambio de tamaño de pantalla
function handleResize() {
    if (window.innerWidth > 1500 && window.innerHeight > 680) {
        // Si es escritorio, mostrar los divs
        var tabs = document.getElementsByClassName("box");
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].style.display = "block";
        }
        document.querySelector(".tabs-mobile").style.display = "none";
    } else {
        document.querySelector(".tabs-mobile").style.display = "block";
        // Agrega la clase 'tab-active' al botón/tab activo
        document.getElementById("btn-" + "screenEditor").classList.add("tab-active");
    }
}

function initTabs(){
    if (window.innerWidth > 1500 && window.innerHeight > 680) {
        // Si es escritorio, mostrar los divs
        var tabs = document.getElementsByClassName("box");
        for (var i = 0; i < tabs.length; i++) {
          tabs[i].style.display = "block";
        }
        document.querySelector(".tabs-mobile").style.display = "none";
    } else {
        // Si es móvil, ocultar los divs y mostrar las pestañas
        document.querySelector(".tabs-mobile").style.display = "block";
        // Agrega la clase 'tab-active' al botón/tab activo
        document.getElementById("btn-" + "screenEditor").classList.add("tab-active");
    }
}

// Manejar el cambio de tamaño de pantalla
window.addEventListener("resize", handleResize);

// Disable long-press text selection inside wasm View
function absorbEvent(event) {
    event.returnValue = false;
}

let div1 = document.querySelector("#screenEditor");
div1.addEventListener("touchstart", absorbEvent);
div1.addEventListener("touchend", absorbEvent);
div1.addEventListener("touchmove", absorbEvent);
div1.addEventListener("touchcancel", absorbEvent);

// User menu style functions
const userMenu     = document.getElementById("user-menu");
const toggleButton = document.getElementById("user-icon");
const dropdownMenu = document.getElementById("user-content");

let userClicked = false
toggleButton.addEventListener("click", function (event) {
    if (!userClicked) {
        dropdownMenu.style.display = "block";
        userMenu.style.background = "#d8e0e8";
    } else {
        dropdownMenu.style.display = "none";
        userMenu.style.background = "gray";
    }
    userClicked = !userClicked;
    event.stopPropagation(); // Evita que el click se propague al document
});

document.addEventListener("click", function (event) {
    // Oculta el menú si se hace clic fuera del botón o del menú
    if (!dropdownMenu.contains(event.target) && !toggleButton.contains(event.target)) {
        dropdownMenu.style.display = "none";
        userMenu.style.background = "gray";
    }
    userClicked = false
});

export { openScreen, initTabs }
