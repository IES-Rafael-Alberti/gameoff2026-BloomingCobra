# Guía de habitaciones (diseñador)

## Cómo funciona (idea general)

El juego **no tiene un mundo único**. Solo hay **una habitación cargada** a la vez.

- `game.tscn` guarda al jugador, HUD, cámara y el `RoomManager`.
- Al cruzar una puerta, el manager **guarda el estado**, **descarga** la sala actual y **carga** la escena destino.
- El mapa estilo Isaac se construye con `map_cell` + enlaces de puertas (no con posiciones en un mundo grande).

---

## Crear una habitación nueva (mínimo)

1. Crea una escena en `assets/scenes/rooms/` (ej. `habitacion_xxx.tscn`).
2. Raíz: `Node2D` con script de sala:
   - genérica: `room.gd`
   - o tipada: `safe.gd`, `trap.gd`, `parkour.gd`, `varied.gd`, `boss_room.gd`, `starting.gd`, etc.
3. En el Inspector de la raíz:
   - **`room_id`**: único (si lo dejas vacío usa el nombre del archivo).
   - **`map_cell`**: celda del minimapa (única; no repetir).
4. Estructura mínima recomendada:

```
HabitacionXxx          ← script Room / Safe / …
├── Switchable         ← script switchable.gd
│   ├── Pesadilla
│   │   └── Tiles      ← TileMapLayer (+ props solo de pesadilla)
│   └── Sueño
│       └── Tiles      ← TileMapLayer (+ props solo de sueño)
├── Walls              ← (opcional) colisiones extra
├── Door…              ← puertas
└── Enemies / props…   ← lo que viva en ambos modos (o bajo un modo)
```

Plantilla útil: `assets/scenes/common/switchable.tscn`.

Referencia real con `TileMapLayer`: `habitacion_descanso.tscn`.

---

## Conectar habitaciones (puertas)

Cada puerta (`door.gd`) necesita:

| Campo | Qué es |
|--------|--------|
| **`door_id`** | Id local (ej. `north`, `south`). Si vacío → nombre del nodo en minúsculas. |
| **`target_room`** | Escena destino (`res://…/habitacion_y.tscn`). Vacío = **pared sellada**. |
| **`target_door_id`** | Puerta de entrada en la sala destino. |
| **`starts_open`** | Si empieza abierta (también si su `CollisionShape2D` está disabled). |

Hijos importantes (se crean solos si faltan, pero conviene colocarlos a mano):

- **`Spawn`** (`Marker2D`): dónde aparece el jugador al **entrar por esta puerta**.
- **`Trigger`**: zona que detecta al jugador cuando la puerta está abierta y enlazada.

### Enlace bidireccional (lo normal)

Sala A, puerta `east`:

- `target_room` → escena B
- `target_door_id` → `west`

Sala B, puerta `west`:

- `target_room` → escena A
- `target_door_id` → `east`

Coloca el `Spawn` **dentro** de la sala, un poco lejos del umbral, para no re-disparar la transición.

---

## Sueño / Pesadilla

Bajo `Switchable`:

- **`Pesadilla`** = modo 0
- **`Sueño`** = modo 1

Todo lo que cuelgue de un modo (tiles + props) **aparece/desaparece** al cambiar.

- Props **solo de un modo** → hijos de ese nodo (`Barriers` bajo Pesadilla, `Breakables` bajo Sueño, etc.).
- Props/enemigos **siempre presentes** → fuera de `Switchable` (o en ambos modos si quieres copias distintas).

Tiles definitivos: **`TileMapLayer`**. Los `TileMap` monolíticos actuales son de debug.

---

## Checklist mínimo para que “funcione”

- [ ] Raíz con script `Room` (o subtipo)
- [ ] `room_id` único
- [ ] `map_cell` único
- [ ] `Switchable` → `Pesadilla` / `Sueño` con al menos un `TileMapLayer` (bounds de cámara)
- [ ] ≥1 puerta con `door_id` + `Spawn` bien colocado
- [ ] Si debe conectar: `target_room` + `target_door_id` válidos (mejor ida y vuelta)

Sin `target_room`, la puerta es **barrera permanente**.

---

## Probar y validar

- **F6** (Run Current Scene) en la escena de la habitación: arranca `game.tscn` empezando en esa sala (con jugador, HUD, etc.). Si ves la sala sola y congelada, el boot no saltó.
- Opcional: un `DefaultSpawn` (`Marker2D`) en la raíz para el punto de aparición con F6; si no hay, usa el centro de los tiles.
- Validador: abre `assets/scripts/tools/validate_room_links.gd` → Script Editor → **File → Run** (`Ctrl+Shift+X`).  
  Comprueba `room_id`, `map_cell`, destinos y (en parte) enlaces recíprocos.

---

## Cosas a tener en cuenta

1. **Una escena = una habitación.** No metas varias salas en el mismo `.tscn` del juego.
2. **No hace falta** meter la sala a mano en `game.tscn`; el manager la carga por la ruta de la puerta.
3. **Enemigos / pickups** van en la escena de la sala; el estado (limpia, pickups cogidos, etc.) lo guarda `RunState` al salir.
4. **Spawners**: `EnemySpawnPoint` + opcionalmente `spawn_enemy_scenes` en la raíz.
5. **Botones que abren puertas**: `unlock_doors_with_buttons` + array de botones en la raíz.
6. **Cámara**: bounds = unión de los tiles de **Pesadilla y Sueño**; `camera_limit_expand` solo amplía el límite visual. Si una sala es más grande que otra, los límites se recalculan al entrar.
7. **Props de un solo modo** deben ir bajo ese modo; si están fuera de `Switchable`, siguen activos en ambos mundos.
8. Tipos de sala cambian reglas (safe, trap, parkour, boss…); elige el script adecuado desde el principio.
