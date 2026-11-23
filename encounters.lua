-- encounters.lua
-- Canonical world catalog for Pudu Fantasy: 4 Chilean biomes, 8 HD-2D stage themes,
-- 9 comic encounters, query helpers, and stage_overrides.json persistence.
-- Pure Lua data and I/O module (zero graphics dependencies; safe in threads or LuaJIT).

local json = require("json")

local Encounters = {}

Encounters.OVERRIDES_FILENAME = "stage_overrides.json"

local function normalizeVec3(x, y, z)
  local len = math.sqrt(x * x + y * y + z * z)
  if len <= 1e-6 then
    return { 0.0, -0.707107, 0.707107 }
  end
  return { x / len, y / len, z / len }
end

--------------------------------------------------------------------------------
-- 1. Four Explorable Biomes (Diagonal Overworld u = 0..118)
--------------------------------------------------------------------------------

Encounters.BIOME_ORDER = { "bosque", "desierto", "costa", "ciudad" }

Encounters.BIOMES = {
  bosque = {
    id = "bosque",
    order = 1,
    name = "Bosque y Plaza Valdiviana",
    shortName = "Bosque Valdiviano",
    uStart = 0,
    uEnd = 38,
    spawnU = 3.8,
    floorTile = "grass_floor",
    pathTile = "stone_floor",
    stageDefault = "bosque",
    accentColor = { 0.34, 0.78, 0.42 },
    stages = { "plaza", "bosque" },
  },
  desierto = {
    id = "desierto",
    order = 2,
    name = "Desierto de Atacama",
    shortName = "Atacama",
    uStart = 38,
    uEnd = 64,
    spawnU = 45.0,
    floorTile = "desert_floor",
    pathTile = "stone_floor",
    stageDefault = "mirador",
    accentColor = { 0.94, 0.64, 0.28 },
    stages = { "mirador", "vereda" },
  },
  costa = {
    id = "costa",
    order = 3,
    name = "Costa y Muelle de Valparaíso",
    shortName = "Valparaíso",
    uStart = 64,
    uEnd = 90,
    spawnU = 71.0,
    floorTile = "coast_floor",
    pathTile = "stone_floor",
    stageDefault = "muelle",
    accentColor = { 0.28, 0.76, 0.88 },
    stages = { "muelle", "pantano" },
  },
  ciudad = {
    id = "ciudad",
    order = 4,
    name = "Ciudad y Gran Oficina",
    shortName = "Gran Oficina",
    uStart = 90,
    uEnd = 118,
    spawnU = 104.0,
    floorTile = "stone_floor",
    pathTile = "mountain_floor",
    stageDefault = "oficina",
    accentColor = { 0.72, 0.56, 0.92 },
    stages = { "esquina", "oficina" },
  },
}

--------------------------------------------------------------------------------
-- 2. Eight HD-2D Stage Themes
--------------------------------------------------------------------------------

Encounters.STAGE_THEME_ORDER = {
  "plaza",
  "bosque",
  "mirador",
  "vereda",
  "muelle",
  "pantano",
  "esquina",
  "oficina",
}

Encounters.STAGE_THEMES = {
  plaza = {
    id = "plaza",
    name = "Plaza Valdiviana",
    biome = "bosque",
    floorTile = "grass_floor",
    pathTile = "stone_floor",
    skyTop = { 0.22, 0.54, 0.88 },
    skyBot = { 0.68, 0.87, 0.96 },
    horizonGlow = { 0.98, 0.90, 0.68 },
    groundA = { 0.30, 0.56, 0.28 },
    groundB = { 0.23, 0.45, 0.23 },
    pathA = { 0.70, 0.67, 0.60 },
    pathB = { 0.58, 0.55, 0.49 },
    accentColor = { 0.96, 0.74, 0.26 },
    ambientColor = { 0.46, 0.52, 0.60 },
    sunColor = { 1.00, 0.94, 0.80 },
    sunDir = normalizeVec3(-0.45, -0.58, 0.68),
    sunEnergy = 1.32,
    props = { "lantern_post", "stone_pedestal", "copihue", "valdivian_shrub", "araucaria_tree" },
  },
  bosque = {
    id = "bosque",
    name = "Claro del Bosque Valdiviano",
    biome = "bosque",
    floorTile = "grass_floor",
    pathTile = "stone_floor",
    skyTop = { 0.14, 0.38, 0.56 },
    skyBot = { 0.48, 0.76, 0.76 },
    horizonGlow = { 0.76, 0.92, 0.78 },
    groundA = { 0.20, 0.46, 0.24 },
    groundB = { 0.14, 0.34, 0.19 },
    pathA = { 0.50, 0.42, 0.30 },
    pathB = { 0.39, 0.32, 0.23 },
    accentColor = { 0.34, 0.82, 0.48 },
    ambientColor = { 0.34, 0.46, 0.44 },
    sunColor = { 0.98, 0.92, 0.72 },
    sunDir = normalizeVec3(-0.55, -0.62, 0.56),
    sunEnergy = 1.22,
    props = { "ancient_tree", "araucaria_tree", "valdivian_fern", "mossy_boulder", "mossy_log", "rewe_totem" },
  },
  mirador = {
    id = "mirador",
    name = "Mirador de Atacama",
    biome = "desierto",
    floorTile = "desert_floor",
    pathTile = "stone_floor",
    skyTop = { 0.18, 0.42, 0.80 },
    skyBot = { 0.92, 0.72, 0.54 },
    horizonGlow = { 1.00, 0.80, 0.48 },
    groundA = { 0.82, 0.58, 0.33 },
    groundB = { 0.68, 0.44, 0.25 },
    pathA = { 0.88, 0.72, 0.48 },
    pathB = { 0.74, 0.58, 0.38 },
    accentColor = { 0.36, 0.84, 0.92 },
    ambientColor = { 0.58, 0.48, 0.42 },
    sunColor = { 1.00, 0.92, 0.74 },
    sunDir = normalizeVec3(-0.38, -0.72, 0.58),
    sunEnergy = 1.48,
    props = { "desert_cactus", "mountain_crystal", "apacheta_sundial", "rock_monolith", "crystal_mirror" },
  },
  vereda = {
    id = "vereda",
    name = "Vereda Soleada de Atacama",
    biome = "desierto",
    floorTile = "desert_floor",
    pathTile = "stone_floor",
    skyTop = { 0.28, 0.50, 0.78 },
    skyBot = { 0.95, 0.78, 0.58 },
    horizonGlow = { 1.00, 0.85, 0.58 },
    groundA = { 0.76, 0.56, 0.36 },
    groundB = { 0.63, 0.45, 0.28 },
    pathA = { 0.80, 0.70, 0.56 },
    pathB = { 0.67, 0.57, 0.44 },
    accentColor = { 0.96, 0.68, 0.24 },
    ambientColor = { 0.56, 0.48, 0.40 },
    sunColor = { 1.00, 0.90, 0.70 },
    sunDir = normalizeVec3(-0.52, -0.60, 0.61),
    sunEnergy = 1.38,
    props = { "desert_cactus", "textile_bale", "lantern_post", "moai_relic", "lettuce_truck" },
  },
  muelle = {
    id = "muelle",
    name = "Muelle de Valparaíso",
    biome = "costa",
    floorTile = "coast_floor",
    pathTile = "stone_floor",
    skyTop = { 0.16, 0.48, 0.82 },
    skyBot = { 0.62, 0.86, 0.96 },
    horizonGlow = { 0.84, 0.95, 0.98 },
    groundA = { 0.20, 0.52, 0.68 },
    groundB = { 0.14, 0.40, 0.56 },
    pathA = { 0.62, 0.48, 0.34 },
    pathB = { 0.48, 0.36, 0.25 },
    accentColor = { 0.28, 0.82, 0.92 },
    ambientColor = { 0.42, 0.54, 0.66 },
    sunColor = { 1.00, 0.96, 0.86 },
    sunDir = normalizeVec3(-0.42, -0.64, 0.64),
    sunEnergy = 1.36,
    props = { "coast_lighthouse", "caleuche_ship", "lantern_post", "pincoya_shrine", "textile_bale" },
  },
  pantano = {
    id = "pantano",
    name = "Pantano Costero Traicionero",
    biome = "costa",
    floorTile = "coast_floor",
    pathTile = "stone_floor",
    skyTop = { 0.18, 0.30, 0.38 },
    skyBot = { 0.46, 0.62, 0.58 },
    horizonGlow = { 0.68, 0.78, 0.64 },
    groundA = { 0.34, 0.42, 0.24 },
    groundB = { 0.24, 0.30, 0.17 },
    pathA = { 0.44, 0.35, 0.24 },
    pathB = { 0.33, 0.26, 0.18 },
    accentColor = { 0.64, 0.84, 0.30 },
    ambientColor = { 0.34, 0.44, 0.38 },
    sunColor = { 0.90, 0.94, 0.78 },
    sunDir = normalizeVec3(-0.48, -0.54, 0.69),
    sunEnergy = 1.08,
    props = { "lily_pad", "log_dam", "mossy_log", "valdivian_fern", "pincoya_shrine" },
  },
  esquina = {
    id = "esquina",
    name = "Esquina del Semáforo Rebelde",
    biome = "ciudad",
    floorTile = "stone_floor",
    pathTile = "mountain_floor",
    skyTop = { 0.18, 0.26, 0.52 },
    skyBot = { 0.76, 0.54, 0.62 },
    horizonGlow = { 0.98, 0.66, 0.46 },
    groundA = { 0.32, 0.34, 0.40 },
    groundB = { 0.24, 0.26, 0.32 },
    pathA = { 0.62, 0.64, 0.68 },
    pathB = { 0.48, 0.50, 0.56 },
    accentColor = { 0.96, 0.30, 0.28 },
    ambientColor = { 0.42, 0.44, 0.56 },
    sunColor = { 1.00, 0.84, 0.66 },
    sunDir = normalizeVec3(-0.62, -0.46, 0.64),
    sunEnergy = 1.24,
    props = { "lantern_post", "debris_pile", "stone_pedestal", "biome_arch", "lettuce_truck" },
  },
  oficina = {
    id = "oficina",
    name = "Gran Oficina de Trámites #999",
    biome = "ciudad",
    floorTile = "stone_floor",
    pathTile = "mountain_floor",
    skyTop = { 0.12, 0.16, 0.34 },
    skyBot = { 0.42, 0.44, 0.64 },
    horizonGlow = { 0.92, 0.82, 0.66 },
    groundA = { 0.36, 0.38, 0.46 },
    groundB = { 0.28, 0.30, 0.38 },
    pathA = { 0.76, 0.22, 0.24 },
    pathB = { 0.58, 0.16, 0.18 },
    accentColor = { 0.94, 0.78, 0.32 },
    ambientColor = { 0.40, 0.40, 0.54 },
    sunColor = { 1.00, 0.93, 0.80 },
    sunDir = normalizeVec3(-0.34, -0.68, 0.65),
    sunEnergy = 1.32,
    props = { "stone_pedestal", "lantern_post", "orb_shrine", "quena_monolith", "biome_arch" },
  },
}

--------------------------------------------------------------------------------
-- 3. Nine Canonical Comic Encounters
--------------------------------------------------------------------------------

Encounters.LIST = {
  {
    index = 1,
    id = "nino_helado",
    name = "Niño del Helado Triple",
    subtitle = "Presumido de la Plaza",
    biome = "bosque",
    stage = "plaza",
    category = "persona",
    u = 10.0,
    v = 0.2,
    maxHp = 100,
    track = "superstar",
    music = "superstar",
    scale = 2.55,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/nino_helado",
    sprite = "assets/sprites/encounters/nino_helado",
    color = { 0.94, 0.52, 0.62 },
    weaknesses = { "lluvia", "nube", "agua", "gaviota", "viento", "sol", "platano" },
    situation = "Presume su helado gigante de 3 bolas bloqueando el camino en la plaza.",
    introLine = "¡Jajá! Mi helado triple es más grande que tú, ciervito. ¡No pasas!",
    semiHintLine = "¡Qué suerte este cielo calmo y sin pájaros glotones! Nada derrite ni bota mi cono...",
    defeatLine = "¡BUAAA! ¡Mis tres bolas de lúcuma y frutilla! ¡Le voy a acusar a mi mamá!",
    moodLabel = "PRESUMIDO",
    tauntLines = {
      "¡Mira qué equilibrio! Tres bolas y cero vergüenza, ciervito.",
      "¿Ese es tu conjuro? Mi barquillo ni tembló un milímetro.",
      "¡Jajá! Con una mano sostengo mi postre y con la otra te gano.",
      "¡Pasa por otro lado, pudú! Esta vereda es zona exclusiva de helado.",
    },
  },
  {
    index = 2,
    id = "mimo_muro",
    name = "Mimo del Muro Invisible",
    subtitle = "Artista Callejero Obstinado",
    biome = "bosque",
    stage = "plaza",
    category = "persona",
    u = 22.0,
    v = -2.0,
    maxHp = 110,
    track = "superstar",
    music = "superstar",
    scale = 2.55,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/mimo_muro",
    sprite = "assets/sprites/encounters/mimo_muro",
    color = { 0.85, 0.86, 0.92 },
    weaknesses = { "pintura", "balde", "abeja", "bocina", "trompeta", "agua", "martillo" },
    situation = "Bloquea la plaza fingiendo un muro invisible y se niega a romper el silencio.",
    introLine = "...*toca el aire con desprecio y te arma un muro invisible en la nariz*...",
    semiHintLine = "*Hace señas orgullosas: su pared no se ve, su traje sigue impecable y nada lo hace gritar...*",
    defeatLine = "¡AY, MI OBRA MAESTRA! ¡ME HICISTE HABLAR, CIERVO PESADO! ¡Me retiro del teatro!",
    moodLabel = "SILENCIOSO",
    tauntLines = {
      "...*pule su vidrio imaginario con un pañuelo invisible y sonríe sobrado*...",
      "...*se tapa los oídos con dramatismo y apunta a un cartel imaginario de PARE*...",
      "...*finge que tu ataque rebotó en su pared invisible con cámara lenta*...",
      "...*hace una reverencia burlona y vuelve a cerrar la puerta que no existe*...",
    },
  },
  {
    index = 3,
    id = "puma_dramatico",
    name = "Puma Dramático",
    subtitle = "Diva Felina del Bosque",
    biome = "bosque",
    stage = "bosque",
    category = "animal",
    u = 34.0,
    v = 1.6,
    maxHp = 120,
    track = "boss",
    music = "boss",
    scale = 2.55,
    offsetX = 0,
    offsetY = 0,
    isSheet = true,
    sheetCols = 4,
    sheetRows = 2,
    sheetRow = 1,
    spritePath = "assets/sprites/puma_painterly_sheet",
    sprite = "assets/sprites/puma_painterly_sheet",
    color = { 0.88, 0.56, 0.24 },
    weaknesses = { "lana", "ovillo", "pepino", "barro", "ducha", "laser", "caja", "secador" },
    situation = "Un puma teatral bloquea el claro presumiendo su melena y pose de rey feroz.",
    introLine = "¡Tiembla, pequeño pudú! Nadie arruinará mi entrada triunfal... ni mi pelaje.",
    semiHintLine = "¡Soy una fiera elegante, jamás un gatito común! Odio despeinarme y detesto los juguetes...",
    defeatLine = "¡NOOO, MI PEINADO DE ESTRELLA! ¡Me rindo, pasa antes de que alguien me vea así!",
    moodLabel = "TEATRAL",
    tauntLines = {
      "¡Admira este perfil andino! Dos horas de cepillado no se tocan.",
      "¡Ja! ¿Crees que un rugido tan regio se distrae con cualquier cosa?",
      "¡Silencio en el claro! Que la fiera necesita luz perfecta para posar.",
      "¡Ni una mota de polvo en mis garras, pequeño ciervo insolente!",
    },
  },
  {
    index = 4,
    id = "turista_selfie",
    name = "Turista del Selfie Infinito",
    subtitle = "Influencer del Mirador",
    biome = "desierto",
    stage = "mirador",
    category = "persona",
    u = 48.0,
    v = -1.2,
    maxHp = 105,
    track = "plaza",
    music = "plaza",
    scale = 2.55,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/turista_selfie",
    sprite = "assets/sprites/encounters/turista_selfie",
    color = { 0.36, 0.78, 0.90 },
    weaknesses = { "lluvia", "nube", "paloma", "espejo", "viento", "barro", "bateria" },
    situation = "Cierra todo el mirador buscando el ángulo perfecto para sus doce seguidores.",
    introLine = "¡Un segundo! ¡No te cruces que arruinas mi foto para mis doce seguidores!",
    semiHintLine = "¡Necesito cielo despejado, cero suciedad en el lente y carga al cien para mi mejor toma!",
    defeatLine = "¡NOOO! ¡Mi encuadre épico se fue a la B! ¡Ya, pasa, voy a borrar el borrador!",
    moodLabel = "POSANDO",
    tauntLines = {
      "¡Aguanta, pudú! Que este filtro de Atacama se me descuadra contigo atrás.",
      "¡Toma cuarenta y ocho! Si sale borrosa, empezamos todo de nuevo.",
      "¡A un lado, porfa! Mis doce seguidores merecen este perfil de oro.",
      "¡Cero interrupciones! Mi celular está al máximo y mi palo selfie también.",
    },
  },
  {
    index = 5,
    id = "gato_guaton",
    name = "Gato Guatón Inamovible",
    subtitle = "Coloso de la Siesta",
    biome = "desierto",
    stage = "vereda",
    category = "animal",
    u = 60.0,
    v = 1.8,
    maxHp = 110,
    track = "plaza",
    music = "plaza",
    scale = 2.45,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/gato_guaton",
    sprite = "assets/sprites/encounters/gato_guaton",
    color = { 0.92, 0.68, 0.30 },
    weaknesses = { "pepino", "caja", "laser", "atun", "pescado", "agua", "aspiradora" },
    situation = "Un gato gigantesco y redondo duerme atravesado en toda la vereda sin moverse.",
    introLine = "Mrrr... ni lo intentes, pudú. Aquí me quedo echado hasta el próximo martes.",
    semiHintLine = "Mrrr... nada me levanta de esta siesta, salvo un aroma marino, un escondite tibio o un susto verde...",
    defeatLine = "¡MIAUUU! ¡Está bien, me muevo dos metros a la sombra! Qué ciervo más cargante...",
    moodLabel = "FLOJO",
    tauntLines = {
      "Mrrr... bostezo nivel experto. Tu conjuro me dio más sueño todavía.",
      "¿Empujarme? Tendrías más suerte moviendo un cerro con una cuchara.",
      "Prrr... este pedazo tibio de vereda tiene mi nombre desde el mediodía.",
      "Sigue probando, ciervito... yo mientras duermo mi cuarta siesta del día.",
    },
  },
  {
    index = 6,
    id = "gaviota_mafiosa",
    name = "Gaviota Mafiosa",
    subtitle = "Jefa del Peaje Portuario",
    biome = "costa",
    stage = "muelle",
    category = "animal",
    u = 74.0,
    v = -1.4,
    maxHp = 115,
    track = "superstar",
    music = "superstar",
    scale = 2.45,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/gaviota_mafiosa",
    sprite = "assets/sprites/encounters/gaviota_mafiosa",
    color = { 0.78, 0.86, 0.96 },
    weaknesses = { "empanada", "espantapajaros", "manguera", "agua", "pescado", "viento" },
    situation = "Cobra peaje ilegal en el muelle con lentes oscuros y mirada de jefa del puerto.",
    introLine = "¡KRA! Impuesto portuario, peludito: pagas el peaje del muelle o no pasas.",
    semiHintLine = "¡Kra! Mientras nadie me tiente con un bocadillo porteño ni me empuje las alas, mando yo.",
    defeatLine = "¡KRA-KRA! ¡Ok, ok, pase libre vitalicio para el ciervo! ¡Nos vemos en la caleta!",
    moodLabel = "MAFIOSA",
    tauntLines = {
      "¡KRA! Qué lindo sombrero, sería una pena que pagara doble impuesto.",
      "En este muelle nadie cruza gratis, ni con cara de pudú inocente.",
      "¡Pff! ¿Eso era un soborno? A mí me conquistas con cosas serias del puerto.",
      "¡Mis lentes oscuros no se mueven y mi tarifa tampoco, compadre!",
    },
  },
  {
    index = 7,
    id = "piscina_barro",
    name = "Pantano Traicionero",
    subtitle = "Trampa Pegajosa del Estero",
    biome = "costa",
    stage = "pantano",
    category = "desafio",
    u = 86.0,
    v = 1.2,
    maxHp = 120,
    track = "boss",
    music = "boss",
    scale = 2.65,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/piscina_barro",
    sprite = "assets/sprites/encounters/piscina_barro",
    color = { 0.44, 0.62, 0.34 },
    weaknesses = { "puente", "madera", "secador", "hielo", "ventisca", "esponja", "sol", "balsa" },
    situation = "Un lodazal burbujeante y burlón engulle botas y corta el paso hacia la ciudad.",
    introLine = "¡Blub-blub! Ven a mojarte las patitas, que tengo hambre de botas limpias...",
    semiHintLine = "¡Blub! Mientras siga bien húmedo y blandito, nadie cruza sin pasarela ni cambio de clima...",
    defeatLine = "¡Glup... glub! ¡Me dejaste más seco y domado que camino de verano! ¡Cruza no más!",
    moodLabel = "PEGAJOSO",
    tauntLines = {
      "¡Blub-blub! Un paso más y tus pezuñas quedan de recuerdo en mi fondo.",
      "¡Plop! Qué delicia de barro fresco, imposible cruzar a pata pelada.",
      "¡Glub! Ese truco ni me hizo cosquillas en las burbujas, ciervito.",
      "¡Sigo igual de pantanoso y feliz! ¿Trajiste botas talla gigante?",
    },
  },
  {
    index = 8,
    id = "semaforo_rebelde",
    name = "Semáforo Rebelde",
    subtitle = "Tirano de la Luz Roja",
    biome = "ciudad",
    stage = "esquina",
    category = "desafio",
    u = 99.0,
    v = -0.8,
    maxHp = 120,
    track = "plaza",
    music = "plaza",
    scale = 2.65,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/semaforo_rebelde",
    sprite = "assets/sprites/encounters/semaforo_rebelde",
    color = { 0.92, 0.32, 0.28 },
    weaknesses = { "pintura", "verde", "trampolin", "rayo", "electrico", "agua", "iman", "martillo" },
    situation = "Se declaró en huelga de luz roja eterna y paralizó toda la esquina céntrica.",
    introLine = "¡ROJO! ¡Y SI ME MIRAS FEO, LO PONGO TODAVÍA MÁS ROJO, CIERVO!",
    semiHintLine = "¡ROJO ETERNO! Solo me ganarían cambiando mi foco de tono, saltándome por arriba o con corte de luz...",
    defeatLine = "¡BZZZT! ¡Luz cambiada a la fuerza... pase peatonal aprobado por decreto del caos!",
    moodLabel = "FURIOSO",
    tauntLines = {
      "¡ALTO AHÍ! Hoy no hay paso peatonal ni para pudúes con sombrero.",
      "¡ROJO INTENSO! Puedes esperar hasta el año tres mil si quieres.",
      "¡BEEP! Infracción por intento de cruce sospechoso, retroceda.",
      "¡Mis circuitos están firmes y mi foco brilla más furioso que nunca!",
    },
  },
  {
    index = 9,
    id = "fila_tramite",
    name = "Tótem de la Fila #999",
    subtitle = "Jefe Final de la Burocracia",
    biome = "ciudad",
    stage = "oficina",
    category = "desafio",
    u = 112.0,
    v = 0.4,
    maxHp = 130,
    track = "boss",
    music = "boss",
    scale = 2.65,
    offsetX = 0,
    offsetY = 0,
    spritePath = "assets/sprites/encounters/fila_tramite",
    sprite = "assets/sprites/encounters/fila_tramite",
    color = { 0.66, 0.52, 0.88 },
    weaknesses = { "sello", "vip", "cafe", "trituradora", "fuego", "viento", "timbre", "tijera" },
    situation = "Una torre viviente de formularios y números eternos custodia la salida de la oficina.",
    introLine = "¡Atendiendo al 004! Tú eres el 999... ¡Y te falta la fotocopia legalizada!",
    semiHintLine = "¡Aquí manda el papeleo infinito! Solo un pase preferente, un buen despertar o acabar con las hojas me frena...",
    defeatLine = "¡TRÁMITE APROBADO EN TIEMPO RÉCORD! ¡Tome su certificado de Héroe Pudú y salga por la alfombra!",
    moodLabel = "BUROCRÁTICO",
    tauntLines = {
      "¡Número 005! Lo siento, joven, su solicitud requiere formulario en triplicado.",
      "¡Rechazado por falta de firma en la esquina inferior derecha!",
      "¡Vuelva después de colación! La ventanilla mágica abre solo los jueves.",
      "¡Ningún ciervo se salta la fila sin papeles en regla y mucha paciencia!",
    },
  },
}

-- Snapshot baseline transform/stage defaults for clean resetOverrides()
Encounters._DEFAULTS = {}
Encounters._BY_ID = {}
for idx, enc in ipairs(Encounters.LIST) do
  enc.index = idx
  Encounters._BY_ID[enc.id] = idx
  Encounters._DEFAULTS[enc.id] = {
    scale = enc.scale,
    offsetX = enc.offsetX,
    offsetY = enc.offsetY,
    u = enc.u,
    v = enc.v,
    stage = enc.stage,
    track = enc.track,
    maxHp = enc.maxHp,
  }
end

--------------------------------------------------------------------------------
-- 4. Query Helpers
--------------------------------------------------------------------------------

function Encounters.count()
  return #Encounters.LIST
end

function Encounters.getById(id)
  if type(id) ~= "string" or id == "" then
    return nil, nil
  end
  local idx = Encounters._BY_ID[id]
  if idx then
    return Encounters.LIST[idx], idx
  end
  for i, enc in ipairs(Encounters.LIST) do
    if enc.id == id then
      Encounters._BY_ID[id] = i
      return enc, i
    end
  end
  return nil, nil
end

function Encounters.getByIndex(idx)
  local n = tonumber(idx)
  if not n then
    return Encounters.LIST[1]
  end
  n = math.floor(n)
  if n < 1 then
    n = 1
  elseif n > #Encounters.LIST then
    n = #Encounters.LIST
  end
  return Encounters.LIST[n]
end

function Encounters.getTheme(stageId)
  if type(stageId) == "string" and Encounters.STAGE_THEMES[stageId] then
    return Encounters.STAGE_THEMES[stageId]
  end
  return Encounters.STAGE_THEMES.plaza
end

function Encounters.getBiome(biomeId)
  if type(biomeId) == "string" and Encounters.BIOMES[biomeId] then
    return Encounters.BIOMES[biomeId]
  end
  return Encounters.BIOMES.bosque
end

function Encounters.getBiomeAtU(u)
  local posU = tonumber(u) or 0
  if posU < 38 then
    return Encounters.BIOMES.bosque
  elseif posU < 64 then
    return Encounters.BIOMES.desierto
  elseif posU < 90 then
    return Encounters.BIOMES.costa
  else
    return Encounters.BIOMES.ciudad
  end
end

function Encounters.getEncountersInBiome(biomeId)
  local out = {}
  local target = (type(biomeId) == "string" and Encounters.BIOMES[biomeId]) and biomeId or "bosque"
  for _, enc in ipairs(Encounters.LIST) do
    if enc.biome == target then
      out[#out + 1] = enc
    end
  end
  return out
end

function Encounters.getByCategory(category)
  local out = {}
  if type(category) ~= "string" or category == "" or category == "todos" or category == "all" then
    for i, enc in ipairs(Encounters.LIST) do
      out[i] = enc
    end
    return out
  end
  for _, enc in ipairs(Encounters.LIST) do
    if enc.category == category then
      out[#out + 1] = enc
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- 5. Overrides Persistence (stage_overrides.json: External BaseDir -> SaveDir)
--------------------------------------------------------------------------------

local function resolveExternalBaseDir(baseDir)
  local dir = baseDir
  if type(dir) ~= "string" or dir == "" then
    if type(love) == "table" and type(love.filesystem) == "table" then
      local okFused, isFused = pcall(love.filesystem.isFused)
      if okFused and isFused then
        local okBase, sbd = pcall(love.filesystem.getSourceBaseDirectory)
        if okBase and type(sbd) == "string" and sbd ~= "" then
          dir = sbd
        end
      else
        local okSrc, src = pcall(love.filesystem.getSource)
        if okSrc and type(src) == "string" and src ~= "" then
          if src:lower():match("%.love$") then
            local okBase, sbd = pcall(love.filesystem.getSourceBaseDirectory)
            if okBase and type(sbd) == "string" and sbd ~= "" then
              dir = sbd
            end
          else
            dir = src
          end
        end
      end
    end
  end
  if type(dir) ~= "string" or dir == "" then
    return nil
  end
  if #dir > 1 then
    dir = dir:gsub("[/\\]+$", "")
  end
  return dir
end

local function prepareObjectForEncode(tbl, jsonMod)
  if type(tbl) ~= "table" then
    return tbl
  end
  if next(tbl) == nil then
    if jsonMod and type(jsonMod.object) == "function" then
      return jsonMod.object({})
    end
    return tbl
  end
  local copy = {}
  for k, v in pairs(tbl) do
    if type(v) == "table" and next(v) == nil and type(k) == "string" then
      if jsonMod and type(jsonMod.object) == "function" then
        copy[k] = jsonMod.object({})
      else
        copy[k] = v
      end
    else
      copy[k] = v
    end
  end
  return copy
end

function Encounters.loadOverrides(baseDir, optBaseDir)
  local jsonMod = json
  local resolvedArg = baseDir
  -- Support optional legacy call loadOverrides(jsonMod, baseDir) cleanly
  if type(baseDir) == "table" and type(baseDir.decode) == "function" then
    jsonMod = baseDir
    resolvedArg = optBaseDir
  end

  local dir = resolveExternalBaseDir(resolvedArg)
  if dir then
    local fullPath = dir .. "/" .. Encounters.OVERRIDES_FILENAME
    local okOpen, f = pcall(io.open, fullPath, "rb")
    if okOpen and f then
      local okRead, raw = pcall(f.read, f, "*a")
      pcall(f.close, f)
      if okRead and type(raw) == "string" and #raw > 0 then
        local okDec, decoded = pcall(jsonMod.decode, raw)
        if okDec and type(decoded) == "table" then
          return decoded, fullPath
        end
      end
    end
  end

  if type(love) == "table" and type(love.filesystem) == "table" and love.filesystem.getInfo then
    local okInfo, info = pcall(love.filesystem.getInfo, Encounters.OVERRIDES_FILENAME)
    if okInfo and info then
      local okRead, raw = pcall(love.filesystem.read, Encounters.OVERRIDES_FILENAME)
      if okRead and type(raw) == "string" and #raw > 0 then
        local okDec, decoded = pcall(jsonMod.decode, raw)
        if okDec and type(decoded) == "table" then
          return decoded, "save:" .. Encounters.OVERRIDES_FILENAME
        end
      end
    end
  end

  return {}, nil
end

function Encounters.saveOverrides(overrides, baseDir, optBaseDir)
  local jsonMod = json
  local data = overrides
  local resolvedArg = baseDir
  -- Support optional legacy call saveOverrides(jsonMod, overrides, baseDir) cleanly
  if type(overrides) == "table" and type(overrides.encode) == "function" and type(baseDir) == "table" then
    jsonMod = overrides
    data = baseDir
    resolvedArg = optBaseDir
  end

  if type(data) ~= "table" then
    return false, "overrides must be a table"
  end

  local payload = prepareObjectForEncode(data, jsonMod)
  local okEnc, encoded = pcall(jsonMod.encode, payload)
  if not okEnc or type(encoded) ~= "string" then
    return false, tostring(encoded)
  end
  local text = encoded .. "\n"

  local dir = resolveExternalBaseDir(resolvedArg)
  local externalErr = nil
  if dir then
    local fullPath = dir .. "/" .. Encounters.OVERRIDES_FILENAME
    local okOpen, f, openErr = pcall(io.open, fullPath, "wb")
    if okOpen and f then
      local okWrite, writeErr = pcall(f.write, f, text)
      pcall(f.close, f)
      if okWrite then
        return true, fullPath
      end
      externalErr = tostring(writeErr)
    else
      externalErr = tostring(openErr or f)
    end
  end

  if type(love) == "table" and type(love.filesystem) == "table" and love.filesystem.write then
    local okWrite, wrote, saveErr = pcall(love.filesystem.write, Encounters.OVERRIDES_FILENAME, text)
    if okWrite and wrote then
      return true, "save:" .. Encounters.OVERRIDES_FILENAME
    end
    return false, tostring(saveErr or externalErr or "love.filesystem.write failed")
  end

  return false, externalErr or "no writable target for stage_overrides.json"
end

function Encounters.resetOverrides()
  for _, enc in ipairs(Encounters.LIST) do
    local def = Encounters._DEFAULTS[enc.id]
    if def then
      enc.scale = def.scale
      enc.offsetX = def.offsetX
      enc.offsetY = def.offsetY
      enc.u = def.u
      enc.v = def.v
      enc.stage = def.stage
      enc.track = def.track
      enc.music = def.track
      enc.maxHp = def.maxHp
    end
  end
end

function Encounters.applyOverrides(overrides)
  if type(overrides) ~= "table" then
    return 0
  end
  local encMap = (type(overrides.encounters) == "table") and overrides.encounters or nil
  local applied = 0

  for _, enc in ipairs(Encounters.LIST) do
    local entry = (encMap and encMap[enc.id]) or overrides[enc.id]
    if type(entry) == "table" then
      local touched = false
      if type(entry.scale) == "number" and entry.scale > 0.1 and entry.scale < 20.0 then
        enc.scale = entry.scale
        touched = true
      end
      if type(entry.offsetX) == "number" then
        enc.offsetX = entry.offsetX
        touched = true
      end
      if type(entry.offsetY) == "number" then
        enc.offsetY = entry.offsetY
        touched = true
      end
      if type(entry.u) == "number" then
        enc.u = entry.u
        touched = true
      end
      if type(entry.v) == "number" then
        enc.v = entry.v
        touched = true
      end
      if type(entry.stage) == "string" and Encounters.STAGE_THEMES[entry.stage] then
        enc.stage = entry.stage
        touched = true
      end
      if type(entry.track) == "string" and entry.track ~= "" then
        enc.track = entry.track
        enc.music = entry.track
        touched = true
      end
      if type(entry.maxHp) == "number" and entry.maxHp >= 10 then
        enc.maxHp = math.floor(entry.maxHp)
        touched = true
      end
      if touched then
        applied = applied + 1
      end
    end
  end

  return applied
end

return Encounters
