if get(g:, 'loaded_yank_remote_url', v:false)
  finish
endif
let g:loaded_yank_remote_url = v:true

let s:save_cpo = &cpo
set cpo&vim

command! -range YankRemoteURL call yank_remote_url#yank_url(<line1>, <line2>)

if get(g:, 'yank_remote_url#auto_cache', v:false)
  call yank_remote_url#_internal_enable_auto_cache()
endif

let &cpo = s:save_cpo
unlet s:save_cpo
