let s:save_cpo = &cpo
set cpo&vim

function s:echo_error(msg) abort
  echohl ErrorMsg
  echomsg printf('[yank-remote-url.vim] %s',
        \  type(a:msg) ==# v:t_string ? a:msg : string(a:msg))
  echohl None
endfunction

let s:cache = {}

function! s:init() abort
  if !empty(s:cache)
    return
  endif

  " set cache as initialize
  call s:set_cache()
endfunction

function! yank_remote_url#_internal_enable_auto_cache() abort
  " register auto-cache
  augroup yank_remote_url_origin#internal_augroup
    autocmd!
    autocmd BufEnter * call timer_start(0, { -> s:set_cache() })
  augroup END
endfunction

function s:set_cache() abort
  let l:git_root = s:find_git_root()
  if empty(l:git_root)
    let s:cache = {
          \ 'remote_url': '',
          \ 'current_branch': '',
          \ 'current_hash': '',
          \ 'type': '',
          \ 'path': '',
          \ }
  else
    let l:url = s:get_remote_url(get(g:, 'yank_remote_url#remote_name', 'origin'))
    let s:cache = {
          \ 'remote_url': s:normalize_url(l:url),
          \ 'current_branch': s:get_current_branch(),
          \ 'current_hash': s:get_current_commit_hash(),
          \ 'type': s:remote_type(l:url),
          \ 'git_root': l:git_root,
          \ 'path': s:get_path(fnamemodify(expand('%'), ':p')),
          \ }
  endif
endfunction

function s:is_current_file_tracked() abort
  if empty(s:cache.path)
    return v:false
  endif
  return v:true
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
        \ ->substitute('^git@github.com:', 'https://github.com/', '')
        \ ->substitute('^ssh://git@', 'https://', '')
        \ ->substitute('\(//.\+\)\(:\d\+\)', '\1', '')
        \ ->substitute('\.git$', '', '')
  return l:normalized
endfunction

function! s:get_remote_url(origin) abort
  let l:got = systemlist('git remote get-url --all ' .. a:origin)[0]
  if v:shell_error !=# 0
    return ''
  endif
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

function! s:get_path(path) abort
  let l:path = systemlist('git ls-files ' .. a:path)
  if empty(l:path)
    return ''
  endif
  return l:path[0]
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
    call s:echo_error('Unsupported clipboard option.')
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

function! yank_remote_url#generate_url(line1, ...) abort
  call s:init()
  if s:cache.git_root ==# ''
    call s:echo_error('It seems like not git directory.')
    return ''
  endif
  if s:cache.remote_url ==# ''
    call s:echo_error('It seems that this repository has no remote one.')
    return ''
  endif
  if s:cache.path ==# ''
    call s:echo_error('It seems untracked file.')
    return ''
  endif

  let l:line1 = a:line1
  let l:line2 = a:0 ==# 0 ? a:line1 : a:1

  " make selectable line number in use command as <Cmd>~<CR>
  let l:another = line('v')
  if l:line1 == l:line2 && l:line1 != l:another
    if l:another < l:line1
      let l:line1 = l:another
    else
      let l:line2 = l:another
    endif
  endif

  let l:base_url = s:cache.remote_url
  let l:path_to_line = s:path_join(
        \ l:base_url,
        \ 'blob',
        \ get(g:, 'yank_remote_url#use_direct_hash', v:true)
        \   ? s:cache.current_hash
        \   : s:cache.current_branch,
        \ s:cache.path,
        \ ) .. s:normalize_linenumber(a:line1, l:line2)

  return l:path_to_line
endfunction

function! yank_remote_url#yank_url(line1, ...) abort
  let l:line2 = a:0 ==# 0 ? a:line1 : a:1
  let l:url = yank_remote_url#generate_url(a:line1, l:line2)
  if !empty(l:url)
    call s:yank(l:url)
  endif
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
