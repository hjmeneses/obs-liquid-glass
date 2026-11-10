# obs-liquid-glass

Shaders para **OBS Studio** que imitan el efecto de vidrio líquido ("Liquid Glass") de iOS: desenfoque, refracción en el bisel, dispersión de color, tinte, brillo de borde y sombra.

*[English below](#english)*

## Requisitos

- OBS Studio
- Plugin [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter)

## Shaders

| Archivo | Qué hace |
|---|---|
| `liquid-glass.shader` | Panel de vidrio rectangular con esquinas redondeadas. Posición, tamaño y radio se ajustan con sliders. Para varios paneles, agrega el filtro varias veces. |
| `liquid-glass-forma.shader` | La forma del vidrio la define **otra fuente o escena** (PNG con transparencia, texto, figuras…). Donde esa fuente es opaca (o blanca, en modo brillo) aparece vidrio que refracta la escena. |

## Instalación

1. Descarga los archivos `.shader` (o clona el repo).
2. En OBS, clic derecho sobre la fuente o escena → **Filtros** → **+** → **User-defined shader**.
3. Activa **Load shader text from file** y elige el archivo `.shader`.
4. Ajusta los parámetros.

### Usar una forma personalizada (`liquid-glass-forma.shader`)

1. Crea una escena aparte, por ejemplo "Forma Vidrio", con las figuras donde quieres el vidrio. Esa escena no tiene que salir en vivo.
2. En la escena principal agrega el filtro con `liquid-glass-forma.shader`.
3. En **Fuente de forma** elige la escena "Forma Vidrio".
4. Si tu forma es blanca sobre negro en lugar de tener transparencia, activa **Usar brillo en vez de transparencia**.

**Tip:** el filtro solo refracta lo que hay en la fuente donde se aplica. Para que el vidrio refracte todo lo que está detrás, aplícalo a la escena completa (o a un grupo del tamaño del canvas).

## Parámetros principales

| Parámetro | Efecto |
|---|---|
| Desenfoque | Radio del blur del contenido detrás del vidrio |
| Refracción | Desplazamiento en el bisel; negativo = efecto lupa |
| Ancho del bisel | Qué tan ancha es la zona curva del borde |
| Dispersión de color | Separación RGB en el bisel (aberración cromática) |
| Saturación / Tinte | Color del vidrio |
| Brillo de borde / Ángulo de la luz | Reflejo especular; *Giro de la luz* lo anima |
| Sombra | Opacidad y tamaño de la sombra proyectada |
| Ondulación líquida / Velocidad | Deformación orgánica animada en el vidrio y sus reflejos |
| Grano de escarcha (Frost) | Textura esmerilada sutil y dispersión aleatoria del desenfoque |
| Perfil del bisel | 0 = curva suave; 1 = convexo tipo iOS, comprime el fondo junto a la orilla |
| Tinte en el bisel | 1 = el tinte se desvanece en el borde (clave para vidrio oscuro) |
| Luz del lado opuesto | Brillo en el lado del borde contrario a la luz |

## Presets con botones (script)

`liquid-glass-presets.lua` agrega botones para aplicar estilos tipo iOS. Escribe los valores en el filtro, así que los sliders quedan ajustables.

1. **Herramientas → Scripts → +** y elige `liquid-glass-presets.lua`.
2. En **Filtro de vidrio** elige tu filtro (si no aparece, **Actualizar lista**).
3. Presiona un preset:

| Preset | Inspirado en | Rasgos |
|---|---|---|
| Control | Botones del Centro de control | Casi sin tinte, fondo muy desenfocado, brillo en dos lados |
| Barra oscura | Barra de búsqueda / Siri | Centro casi negro, el bisel deja ver el fondo refractado |
| Panel grande | Carpetas | Desenfoque fuerte, tinte oscuro ligero, bisel fino |

También puedes **guardar tus valores actuales** con un nombre y aplicarlos después en otros filtros. Si tenías abiertas las propiedades del filtro, ciérralas y ábrelas de nuevo para ver los sliders actualizados.

---

## English

Shaders for **OBS Studio** that mimic the iOS "Liquid Glass" look: background blur, bezel refraction, chromatic dispersion, tint, rim highlight and drop shadow.

### Requirements

- OBS Studio
- [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter) plugin

### Shaders

| File | What it does |
|---|---|
| `liquid-glass.shader` | Rounded-rectangle glass panel. Position, size and corner radius are slider controls. Add the filter multiple times for several panels. |
| `liquid-glass-forma.shader` | The glass shape comes from **another source or scene** (transparent PNG, text, shapes…). Wherever that source is opaque (or white, in luminance mode) you get glass refracting the scene. |

### Install

1. Download the `.shader` files (or clone the repo).
2. In OBS, right-click a source or scene → **Filters** → **+** → **User-defined shader**.
3. Enable **Load shader text from file** and pick the `.shader` file.
4. Tweak the parameters (labels are in Spanish).

### Custom shape (`liquid-glass-forma.shader`)

1. Create a separate scene, e.g. "Glass Shape", containing the shapes you want as glass. It doesn't need to go live.
2. Add the filter with `liquid-glass-forma.shader` to your main scene.
3. Set **Fuente de forma** (shape source) to that scene.
4. If your shape is white-on-black instead of using transparency, enable **Usar brillo en vez de transparencia** (use luminance).

**Tip:** the filter can only refract what's inside the source it's applied to. To refract everything behind it, apply it to the whole scene (or a canvas-sized group).

### Main parameters

| Parameter (label in OBS) | Effect |
|---|---|
| Blur (*Desenfoque*) | Blur radius of the content behind the glass |
| Refraction (*Refracción*) | Bezel displacement; negative = magnifier effect |
| Bezel width (*Ancho del bisel*) | How wide the curved edge zone is |
| Color dispersion (*Dispersión de color*) | RGB split at the bezel (chromatic aberration) |
| Saturation / Tint (*Saturación / Tinte*) | Glass color |
| Rim highlight / Light angle (*Brillo de borde / Ángulo de la luz*) | Specular reflection; *Giro de la luz* animates it |
| Shadow (*Sombra*) | Drop shadow opacity and size |
| Liquid wave / Speed (*Ondulación líquida / Velocidad*) | Animated organic distortion of the glass and its reflections |
| Frost grain (*Grano de escarcha*) | Subtle frosted texture and randomized blur scattering |
| Bezel profile (*Perfil del bisel*) | 0 = soft curve; 1 = iOS-like convex, squeezes the background at the rim |
| Bezel tint (*Tinte en el bisel*) | 1 = tint fades out at the edge (key for dark glass) |
| Back light (*Luz del lado opuesto*) | Highlight on the rim side facing away from the light |

### Presets with buttons (script)

`liquid-glass-presets.lua` adds one-click iOS-style presets. It writes the values into the filter, so the sliders stay adjustable.

1. **Tools → Scripts → +** and pick `liquid-glass-presets.lua`.
2. Choose your filter under **Filtro de vidrio** (use **Actualizar lista** if it's missing).
3. Click a preset: **Control** (Control Center buttons), **Barra oscura** (dark search bar / Siri), **Panel grande** (folders).

You can also save your current values under a name and reuse them on other filters. If the filter's properties window was open, reopen it to see the updated sliders.

## Licencia / License

[MIT](LICENSE)

*Inspirado en el diseño Liquid Glass de Apple. Proyecto independiente, sin relación con Apple Inc. / Inspired by Apple's Liquid Glass design. Independent project, not affiliated with Apple Inc.*
