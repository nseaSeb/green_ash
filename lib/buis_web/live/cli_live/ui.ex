defmodule BuisWeb.CliLive.UI do
  @moduledoc """
  Éléments d'UI partagés par les écrans de la console CLI :
  la feuille de style "terminal vert" plein écran, et le cadre commun
  (en-tête, filet, ligne de message, ligne de commande, légende des touches).
  """
  use BuisWeb, :html

  @doc "Feuille de style du terminal. À inclure une fois par écran."
  def styles(assigns) do
    ~H"""
    <style>
      html, body { margin:0; background:#001b00; }
      .crt {
        position: fixed; inset: 0;
        background:#001b00; color:#33ff5e;
        font-family: ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace;
        font-size: 15px; line-height: 1.5;
        padding: 1.1rem 1.5rem; display:flex; flex-direction:column; overflow:hidden;
        text-shadow: 0 0 2px rgba(51,255,94,.35);
      }
      .crt * { box-sizing: border-box; }
      .crt-head { display:flex; justify-content:space-between; text-transform:uppercase; letter-spacing:.12em; }
      .crt-title { flex:1; text-align:center; font-weight:700; }
      .crt-rule { border-top:1px solid #1f7a34; margin:.5rem 0 1rem; }
      .crt-body { flex:1; overflow:auto; }
      .crt-lead { color:#9dffb8; margin:0 0 1rem; }
      .crt-opt { display:flex; gap:1rem; padding:.12rem .3rem; cursor:pointer; }
      .crt-opt:hover, .crt-opt.sel { background:#063d13; }
      .crt-num { width:3ch; text-align:right; color:#7dffa0; }
      .crt-detail { margin-left:auto; color:#5fbf78; }
      .crt-foot { margin-top:1rem; }
      .crt-msg { min-height:1.3em; color:#ffd166; }
      .crt-cmd { display:flex; gap:.6rem; align-items:center; margin:.3rem 0 .5rem; }
      .crt-cmd label { color:#9dffb8; white-space:nowrap; }
      .crt-cmd input { flex:1; background:#000; color:#33ff5e; border:0; border-bottom:1px solid #33ff5e; padding:.2rem .1rem; font:inherit; }
      .crt-cmd input:focus { outline:none; background:#021a06; }
      .crt-keys { color:#5fbf78; letter-spacing:.02em; font-size:.9em; }
      .crt-keys b { color:#33ff5e; }
      /* champs de formulaire (écran d'action) */
      .crt .fieldset { margin-bottom:.9rem; max-width:560px; }
      .crt input[type=text], .crt input[type=number], .crt input[type=date],
      .crt input[type=datetime-local], .crt input[type=email], .crt input[type=password],
      .crt select, .crt textarea {
        background:#000; color:#33ff5e; border:1px solid #1f7a34; border-radius:0;
        padding:.3rem .5rem; width:100%; font:inherit;
      }
      .crt input:focus, .crt select:focus, .crt textarea:focus { outline:1px solid #33ff5e; }
      .crt .label { color:#7dffa0; text-transform:uppercase; font-size:.72em; letter-spacing:.09em; display:block; margin-bottom:.15rem; }
      .crt .btn, .crt button[type=submit] { background:#33ff5e; color:#001b00; border:0; border-radius:0; padding:.35rem 1rem; font:inherit; font-weight:700; cursor:pointer; }
      .crt-linkbtn { background:transparent; color:#33ff5e; border:1px dashed #1f7a34; padding:.3rem .7rem; font:inherit; cursor:pointer; }
      .crt-pre { background:#000; border:1px solid #1f7a34; padding:.6rem; white-space:pre-wrap; word-break:break-word; font-size:.85em; margin-top:.5rem; }
      .crt-ok { color:#7dffa0; } .crt-err { color:#ff6b6b; }
      /* subfile (listes) */
      .crt table.sf { border-collapse:collapse; width:100%; margin-top:.4rem; }
      .crt table.sf th, .crt table.sf td { text-align:left; padding:.12rem .7rem .12rem 0; border-bottom:1px dotted #0c5a1f; white-space:nowrap; }
      .crt table.sf th { color:#7dffa0; text-transform:uppercase; font-size:.72em; letter-spacing:.06em; }
      .crt .sf-opt { width:3ch; background:#000; color:#33ff5e; border:1px solid #1f7a34; text-align:center; font:inherit; padding:.1rem; }
      .crt table.sf tr.exp td { background:#042808; }
      .crt-legend { color:#9dffb8; }
      .crt-legend b { color:#33ff5e; }
      .crt-confirm { border:1px solid #ff6b6b; padding:.6rem .8rem; margin-bottom:1rem; display:flex; gap:1rem; align-items:center; flex-wrap:wrap; }
      .crt-confirm p { margin:0; flex:1; }
    </style>
    """
  end
end
