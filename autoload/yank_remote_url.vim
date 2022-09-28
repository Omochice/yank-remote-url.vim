let s:save_cpo = &cpo
set cpo&vim

let s:cache = {}

function! yank_remote_url#_internal_initialize() abort
  if !empty(s:cache)
    return
  endif

  " set cache as initialize
  call timer_start(0, { -> s:set_cache() })

  " register auto-cache
  augroup yank_remote_url_origin#internal_augroup
    autocmd!
    autocmd BufEnter * call timer_start(0, { -> s:set_cache() })
  augroup END
endfunction

function s:set_cache() abort
  let l:url = s:get_remote_url('origin')
  let s:cache = {
        \ 'remote_url': s:normalize_url(l:url),
        \ 'current_branch': s:get_current_branch(),
        \ 'current_hash': s:get_current_commit_hash(),
        \ 'type': s:remote_type(l:url),
        \ }
endfunction

function! s:remote_type(url) abort
  if a:url =~# 'github.com'
    return 'github'
  elseif a:url =~# 'gitlab'
    " is this ok for self-hosted?
    return 'gitlab'
  elseif a:url =~# 'gitbucket'
    return 'gitbucket'
  else
    return 'unknown'
  endif
endfunction

function! s:normalize_url(url) abort
  let l:normalized = a:url
        \ ->substitute('^ssh://git@', 'https://', '')
        \ ->substitute('\(//.\+\)\(:\d\+\)', '\1', '')
        \ ->substitute('\.git$', '', '')
  return l:normalized
endfunction

function! s:get_remote_url(origin) abort
  let l:got = systemlist('git remote get-url --all ' .. a:origin)[0]
  return l:got
endfunction

function! s:get_current_branch() abort
  let l:branch = systemlist('git branch --show-current')[0]
  return l:branch
endfunction

function! s:get_current_commit_hash() abort
  let l:hash = systemlist('git rev-parse HEAD')[0]
  return l:hash
endfunction

function! s:yank_to_clipboard(register) abort
  let l:raw_url = s:get_remote_url()
  let l:normalized = s:normalize(l:raw_url)
  execute 'let @' .. a:register .. ' = ' .. string(l:normalized)
endfunction

function! s:normalize_linenumber(line1, line2) abort
  let l:head = '#'
  if a:line1 ==# a:line2
    return l:head .. 'L' .. string(a:line1)
  endif

  let l:line_separator = s:cache.type ==# 'gitlab' ? '-' : '+'
  return l:head .. 'L' .. string(a:line1) .. l:line_separator .. 'L' .. string(a:line2)
endfunction

function! s:find_git_root() abort
  let l:path = fnamemodify(expand('%'), ':p')
  while v:true
    if isdirectory(l:path .. '/.git')
      return l:path
    endif
    let l:modified = fnamemodify(l:path, ':h')
    if l:modified ==# l:path
      " is /
      return ''
    endif
    let l:path = l:modified
  endwhile
endfunction

function! s:yank(string) abort
  let l:clipboards = &clipboard->split(',')
  if l:clipboards->index('unnamedplus') !=# -1 ||
        \ l:clipboards->index('autoselectplus')
    execute 'let' '@+' '=' string(a:string)
    return
  if l:clipboards->index('unnamed') !=# -1 ||
        \ l:clipboards->index('autoselect') !=# -1
    execute 'let' '@*' '=' string(a:string)
    return
  else
    echohl ErrorMsg
    echomsg printf('[yank-remote-url.vim] Unsupprted clipboard option.')
    echohl None
  endif
endfunction

function! s:path_join(...) abort
  return a:000
        \ ->copy()
        \ ->map({_, val -> v:val
        \                   ->substitute('^/', '', '')
        \                   ->substitute('/$', '', '')})
        \ ->join('/')
endfunction

" GitHub: path/to/repo/blob/path/to/file#L1+L~
" GitLab: path/to/repo/~/blob/path/to/file#L1-L~
" GitBacket: path/to/repo/blob/path/to/file#L1+L~

function! yank_remote_url#generate_url(line1, line2) abort
  call s:init()
  let l:git_root = s:find_git_root()
  if l:git_root ==# ''
    return
  endif

  let l:modifier = [':s', l:git_root, '']->join('|')
  let l:relative_path = fnamemodify(expand('%'), l:modifier)
  let l:base_url = s:cache.remote_url
  let l:path_to_line = s:path_join(
        \ l:base_url,
        \ 'blob',
        \ s:cache.current_branch,
        \ l:relative_path,
        \ ) .. s:normalize_linenumber(a:line1, a:line2)

  return l:path_to_line
endfunction

function! yank_remote_url#yank_url(line1, line2) abort
  let l:url = yank_remote_url#generate_url(a:line1, a:line2)
  call s:yank(l:url)
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
