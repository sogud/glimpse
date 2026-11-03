# Glimpse macOS interface

## 1. Visual theme and atmosphere

A quiet, warm photo workspace, not a model control panel. Photos and the next useful action lead; settings and diagnostics stay secondary. The distinctive element is a consistent three-step strip: 开始分类 → 检查结果 → 加入相册.

Visual thesis: warm neutral surfaces, ink-like text, a restrained leaf-green action color, and a photo contact sheet.
Content plan: orient the user, show readiness, offer one primary action, then disclose details.
Interaction thesis: no decorative animation. Native button press/focus feedback and immediate state updates make frequent review feel fast; keyboard actions never animate.

## 2. Color palette and roles

AppKit uses named dynamic NSColor tokens, not CSS or a web layer. Light / dark values:

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Canvas | #F7F8F4 | #171D19 | Main workspace |
| Sidebar | #E9EDE6 | #202922 | Task navigation |
| Surface | #FFFFFF | #29332C | Photo tiles and inputs |
| Ink | #252E28 | #EEF2EA | Headings and body |
| Muted | #58665C | #AFBDB2 | Supporting text |
| Accent | #306647 | #A5D0B2 | Current step and primary action |
| Action fill | #306647 | #306647 | White primary button text retains contrast in both appearances |
| Divider | #D4DDD3 | #48564B | Thin section separation |

System warning/error colors retain their meaning. Disabled controls use native disabled styling; state is also explained in text, never just color.

## 3. Typography rules

Use SF Pro with AppKit's system CJK fallback (PingFang SC for Chinese). Native menu, focus, and input metrics matter more than importing a display font. Brand words: calm, legible, precise. No negative tracking on Chinese.

| Role | Size | Weight |
| --- | --- | --- |
| Workspace heading | 26 pt | Semibold |
| Analysis count | 34 pt | Semibold, monospaced digits |
| Section heading | 16 pt | Semibold |
| Primary action | 14 pt | Semibold |
| Body / field | 13 pt | Regular |
| Supporting label | 12 pt | Regular |

Wrap explanations naturally. Keep dynamic counts in short complete phrases; do not tail-truncate a count or album name in confirmation.

## 4. Component stylings

- Primary buttons: native rounded bezel, large control size, 40 pt minimum height, dark-green fill with white text, one per work surface. Native highlighted/pressed and keyboard focus states are retained.
- Secondary buttons: standard native bezel or inline disclosure; no competing green fills. Disabled actions retain an adjacent explanation.
- Fields: label above the input when space allows; model and source menus use readable names. Endpoint and scheme editors live in an inline settings disclosure.
- Photo tiles: 12 pt radius, white/dark surface, subtle 1 pt divider, no decorative shadow. Image, scheme/reason, category, include checkbox, detail action. Loading/error placeholders stay small and explicitly labeled.
- Navigation: a quiet sidebar with a clear new-batch action and task state. A plain native table with custom row selection uses a 12% accent tint and normal ink text; the source-list style must not replace it with a saturated blue row. Destructive record removal is secondary and remains confirmed.

## 5. Layout principles

Spacing scale: 4, 8, 12, 16, 24, 32 pt. Main leading/trailing inset: 28 pt; sidebar: 16 pt. Form content starts at the top of its scroll viewport even when shorter than that viewport. Main action rows stay outside the scroll area.

Creation shows scope and batch size first, then model readiness. One click fixes the batch and starts analysis. Progress explains what is happening and what will happen next. Review shows photos first, with counts and filters above and the next action below. Keep the review tiles at 368 pt high: a 204 pt photo leads, with category selection and a compact inclusion/detail row below. Split review tools into filter/selection and secondary actions; wrap these groups at narrow detail widths. The sidebar reserves its upper area for creating and finding batches, with refresh and record removal below. On creation, keep readiness and actionable errors visible while model selection and diagnostics live in the connection settings disclosure. Mapping and confirmation use fixed headers/footers and scroll only their album rows.

## 6. Depth and elevation

Sidebar, canvas, and photo surfaces differ by background lightness. Section rules are thin. Only native sheets float above their parent; no glass panels, gradients, or stacks of generic dashboard cards.

## 7. Do's and don'ts

- Use “开始分类”, “检查结果”, and “加入相册” consistently. Do not ask users to understand internal task states or “映射”.
- Explain that classification does not modify Photos. “待删除” remains a suggestion, never a delete operation.
- Show a clear next step for offline, checking, unloaded, busy, empty, paused, applied, and interrupted states.
- Keep the actual model ID in diagnostics, not as the main model label.
- Keep actual album names, photo counts, and skip choices visible before confirmation. Cancel emits no write.
- Keep completed and interrupted tasks read-only. Do not weaken the frozen write confirmation or cancellation rules.
- Do not invent model throughput, classification accuracy, or award scores.
- Keep native/CLI progress separate, personal stores untouched, and all test data synthetic.


## 8. Responsive behavior

Main window minimum: 980 × 680 pt; normal: 1180 × 780 pt. Sidebar starts at 230 pt. Check minimum width, minimum height, both together, and normal. Detail components must also work in a 720 × 658 pt viewport. Review tiles reflow without horizontal scrolling. Long model/album names wrap or use a readable popup, never push the primary action offscreen.

Check light/dark appearance, tab focus, accessible control labels, unloaded/offline/busy/empty/read-only states, target editing, and cancelling final confirmation. Recalculate the native key-view loop when detail controls change so Tab can leave the sidebar and reach enabled fields. Sidebar rows fit their scroll viewport; waiting for an active request to stop is “正在暂停” in both navigation and detail, not “已暂停”. Evidence comes from rendered AppKit components with synthetic data; full-app/PhotoKit acceptance is separately required.
