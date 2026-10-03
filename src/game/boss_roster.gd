class_name BossRoster
extends RefCounted
## User's campaign order; an entry becomes playable only after its encounter passes.
const ORDER: Array[StringName] = [&"valus", &"quadratus", &"gaius", &"phaedra", &"avion", &"barba", &"hydrus", &"kuromori", &"basaran", &"dirge", &"celosia_cenobia", &"pelagia", &"phalanx", &"argus", &"malus", &"devil", &"phoenix", &"spider", &"worm", &"saru", &"dormin"]
const NAMES := {&"valus": "Valus", &"quadratus": "Quadratus", &"gaius": "Gaius", &"phaedra": "Phaedra", &"avion": "Avion", &"barba": "Barba", &"hydrus": "Hydrus", &"kuromori": "Kuromori", &"basaran": "Basaran", &"dirge": "Dirge", &"celosia_cenobia": "Celosia + Cenobia", &"pelagia": "Pelagia", &"phalanx": "Phalanx", &"argus": "Argus", &"malus": "Malus", &"devil": "Devil", &"phoenix": "Phoenix", &"spider": "Spider", &"worm": "Worm", &"saru": "Saru", &"dormin": "Dormin"}
const HINTS := {
	&"barba": "Ukryj się pod łukiem. Gdy strażnik się pochyli, złap brodę.",
	&"basaran": "Zwab strażnika nad gejzer. Strzel w odsłoniętą stopę i wejdź na zad.",
	&"dirge": "Jedź na Agro, traf oko. Po zderzeniu ze ścianą wejdź na grzbiet.",
	&"pelagia": "Wejdź od tyłu. Cios w kamienny ząb kieruje strażnika ku ruinie.",
	&"phalanx": "Przebij trzy worki łukiem. Przy niskim skrzydle: chwyt + skok z Agro.",
	&"argus": "Zwab stomp na oznaczoną płytę, uniknij go i przejdź podniesioną galerią.",
	&"malus": "Korzystaj z osłon. Znak za plecami otwiera drogę po dłoni; łuk odsłania nadgarstek."
}
const LEGACY: Array[StringName] = [&"valus", &"quadratus", &"gaius", &"phaedra", &"hydrus", &"avion"]
# Update after acceptance tests, never infer readiness from the presence of a file.
const PLAYABLE: Array[StringName] = ORDER

static func label(kind: StringName) -> String:
	return NAMES.get(kind, String(kind).capitalize())

static func scene(kind: StringName) -> String:
	return "res://scenes/%s_arena.tscn" % kind
