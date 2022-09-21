let s:save_cpo = &cpo
set cpo&vim

function! s:convert_ssh2https(url) abort
  let l:converted = a:url
        \ ->substitute('^ssh://git@', 'https://', '')
        \ ->substitute(':\d\+', '', '')
        \ ->substitute('\.git$', '', '')
  return l:converted
endfunction

function! s:get_remote_url() abort
  let l:origin = get(g:, 'yank_remote_url_origin', 'origin')
  let l:got = systemlist('git remote get-url --all ' .. l:origin)[0]
  return l:got
endfunction

function! s:yank_to_remote() abort
  let l:raw_url = s:get_remote_url()
  let l:base_url = l:raw_url =~# '^ssh'
        \ ? s:convert_ssh2https(l:raw_url)
        \ : l:raw_url
  execute 'let @' .. get(g:, 'yank_remote_url_origin_register', '+') .. ' = ' .. l:base_url
endfunction



let &cpo = s:save_cpo
unlet s:save_cpo
