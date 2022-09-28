if get(g:, 'loaded_yank_remote_url', v:false)
  finish
endif
let g:loaded_yank_remote_url = v:true

let s:save_cpo = &cpo
set cpo&vim

command! -range YankRemoteURL call yank_remote_url#yank_url(<line1>, <line2>)

let &cpo = s:save_cpo
unlet s:save_cpo
