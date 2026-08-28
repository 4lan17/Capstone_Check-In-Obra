# Check-In-Obra — Design System
Generado con `ui-ux-pro-max-skill` (nextlevelbuilder/ui-ux-pro-max-skill) — curado a mano entre dominios.

> **Nota de método:** el generador automático de la skill (`--design-system`) coincidió con la categoría
> "Inventory & Stock Management" para el color y con un patrón de landing page tipo SaaS que no aplica a
> una app móvil de campo. Además, según la consulta exacta, la tipografía saltó entre pares muy distintos
> (uno incluso de mood "académico/biblioteca", claramente un falso positivo). Por eso este documento combina
> resultados de consultas específicas por dominio (`--domain color`, `--domain typography`, `--domain icons`,
> `--domain ux`) en vez de aceptar un único run automático completo.

---

## Categoría de producto (confirmada)
**Inventory & Stock Management** — keywords: inventory, stock, warehouse, barcode, sku, management.
Coincide con el proyecto real: escaneo de código, niveles de stock, alertas de bajo stock/vencidos.

## Paleta de color
Se combinan dos entradas del catálogo: la de la categoría de producto (funcional) y la de
**Construction/Architecture** (más específica al rubro), para status colors semáforo.

| Rol | Hex | Uso |
|---|---|---|
| Primary | `#334155` | Texto principal, navegación, headers de tabla |
| Secondary | `#64748B` | Texto secundario, íconos inactivos |
| Accent / CTA | `#EA580C` | Acción primaria — *safety orange*, específico de "Construction/Architecture" en el catálogo, más coherente con el rubro que el verde genérico de "Inventory" |
| Background | `#F8FAFC` | Fondo de pantalla |
| Card | `#FFFFFF` | Superficies |
| Border | `#E2E8F0` | Bordes, separadores |
| Success (stock ok / a tiempo) | `#059669` | Semáforo — verde |
| Warning (stock bajo / por vencer) | `#D97706` | Semáforo — ámbar |
| Destructive (vencido / stock crítico) | `#DC2626` | Semáforo — rojo |

*Esta paleta es prácticamente la misma que usamos a mano en el mockup anterior (naranja seguridad + acero + semáforo). La skill la valida en vez de contradecirla — buena señal de que la elección original no era arbitraria.*

## Tipografía
Del dominio `typography` con consulta específica ("utilitarian industrial technical field data"),
resultado **"Dashboard Data"**: mono + sans, pensado para paneles de datos técnicos.

- **Heading / UI:** Fira Sans
- **Datos / códigos / timestamps:** Fira Code (monoespaciada)
- Import: `https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500;600;700&family=Fira+Sans:wght@300;400;500;600;700&display=swap`

Es el mismo concepto que ya aplicamos con Inter + IBM Plex Mono — misma lógica (sans para UI, mono para datos duros), fuente distinta. Cualquiera de los dos pares es válido; mantener el que ya está implementado en el mockup evita retrabajo.

## Estilo
**Flat Design** — 2D, sin sombras pesadas, formas simples, tipografía como protagonista.
Coincide con lo ya construido (bracket-frame lineal, sin gradientes, iconos outline).

## Iconografía
Librería recomendada por la skill: **Phosphor Icons**, estilo *outline*.
`import { Camera, QrCode, Package, Bell } from '@phosphor-icons/react'`

## Reglas UX aplicables (dominio `ux`, con impacto directo en las pantallas ya diseñadas)
1. **Badges/chips no deben quebrar línea.** Los chips de estado ("A TIEMPO", "VENCIDA") deben mantenerse en una sola línea con ancho flexible — ya cumplido en el mockup, mantenerlo al implementar.
2. **Actualizaciones de estado en vivo deben anunciarse de forma atómica** (`role="status" aria-atomic="true"`), no como número suelto — relevante para cuando una herramienta pasa de "a tiempo" a "vencida" en la pantalla de Alertas en tiempo real.
3. **Contraste mínimo 4.5:1** en modo claro, foco visible para navegación por teclado (aplica al panel web de Jefe de Terreno/Admin, no solo a la app móvil).

## Checklist pre-entrega (de la skill)
- [ ] Sin emojis como íconos — usar SVG (Phosphor)
- [ ] `cursor: pointer` en todo elemento clickeable (versión web)
- [ ] Transiciones 150–300ms, `prefers-reduced-motion` respetado
- [ ] Responsive: 375px / 768px / 1024px / 1440px
- [ ] Contraste de texto 4.5:1 mínimo en modo claro
