localStorage = window.localStorage;

function loadModule(identifier, unit) {
	// the start page only renders the default range server-side,
	// so fetch the content for other ranges on demand
	var module = document.getElementsByClassName(identifier + "_" + unit)[0];
	if (module !== undefined && module.childElementCount === 0) {
		var names = {
			'topartists': 'charts_artists',
			'toptracks': 'charts_tracks',
			'topalbums': 'charts_albums',
			'pulse': 'pulse'
		};
		if (!(identifier in names)) return;
		var xhttp = new XMLHttpRequest();
		xhttp.onreadystatechange = function() {
			if (this.readyState == 4 && this.status == 200) {
				var m = document.getElementsByClassName(identifier + "_" + unit)[0];
				if (m !== undefined) m.innerHTML = this.responseText;
				if (typeof lazyLoadInstance !== 'undefined') lazyLoadInstance.update();
			}
		};
		xhttp.open("GET", "/startpage_partial/" + names[identifier] + "/" + unit, true);
		xhttp.send();
	}
}

function showStats(identifier,unit) {
	// Make all modules disappear
	var modules = document.getElementsByClassName("stat_module_" + identifier);
	for (var i=0;i<modules.length;i++) {
		//modules[i].setAttribute("style","width:0px;overflow:hidden;")
		// cheesy trick to make the allocated space always whatever the biggest module needs
		// somehow that messes up pulse on the start page tho
		modules[i].setAttribute("style","display:none;");
	}

	loadModule(identifier, unit);

	// Make requested module appear
	var reactivate = document.getElementsByClassName(identifier + "_" + unit);
	for (var i=0;i<reactivate.length;i++) {
		reactivate[i].setAttribute("style","");
	}

	// Set all selectors to unselected
	var selectors = document.getElementsByClassName("stat_selector_" + identifier);
	for (var i=0;i<selectors.length;i++) {
		selectors[i].setAttribute("style","");
	}

	// Set the active selector to selected
	var reactivate = document.getElementsByClassName("selector_" + identifier + "_" + unit);
	for (var i=0;i<reactivate.length;i++) {
		reactivate[i].setAttribute("style","opacity:0.5;");
	}

	links = document.getElementsByClassName("stat_link_" + identifier);
	for (let l of links) {
		var a = l.href.split("=");
		a.splice(-1);
		a.push(unit);
		l.href = a.join("=");
	}

}


function showStatsManual(identifier,unit) {
	showStats(identifier,unit);
	//neo.setCookie("rangeselect_" + identifier,unit);
	localStorage.setItem("statselect_" + identifier,unit);
}



document.addEventListener('DOMContentLoaded',function() {
	for (var key of Object.keys(defaultpicks)) {
		var val = localStorage.getItem("statselect_" + key);
		if (val != null) {
			showStats(key,val);
		}
		else {
			showStats(key,defaultpicks[key]);
		}


	}
})
