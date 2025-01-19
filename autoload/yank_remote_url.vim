let s:save_cpo = &cpo
set cpo&vim

function s:echo_error(msg) abort
  echohl ErrorMsg
  echomsg printf('[yank-remote-url.vim] %s',
        \  type(a:msg) ==# v:t_string ? a:msg : string(a:msg))
  echohl None
endfunction

function! s:init() abort
  if exists('b:yank_remote_url_cache')
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
  const l:git_root = s:find_git_root()
  if empty(l:git_root)
    let b:yank_remote_url_cache = #{
          \ remote_url: '',
          \ current_branch: '',
          \ current_hash: '',
          \ type: '',
          \ path: '',
          \ }
  else
    const l:url = s:get_remote_url(get(g:, 'yank_remote_url#remote_name', 'origin'))
    let b:yank_remote_url_cache = #{
          \ remote_url: s:normalize_url(l:url),
          \ current_branch: s:get_current_branch(),
          \ current_hash: s:get_current_commit_hash(),
          \ type: s:remote_type(l:url),
          \ git_root: l:git_root,
          \ path: expand('%')
          \       ->fnamemodify(':p')
          \       ->substitute('^' .. l:git_root, '', ''),
          \ }
  endif
endfunction

function s:is_current_file_tracked() abort
  if empty(b:yank_remote_url_cache.path)
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
  const l:normalized = a:url
        \ ->substitute('^git@github.com:', 'https://github.com/', '')
        \ ->substitute('^ssh://git@', 'https://', '')
        \ ->substitute('\(//.\+\)\(:\d\+\)', '\1', '')
        \ ->substitute('\.git$', '', '')
  return l:normalized
endfunction

function! s:get_remote_url(origin) abort
  const l:got = systemlist('git remote get-url --all ' .. a:origin)[0]
  if v:shell_error !=# 0
    return ''
  endif
  return l:got
endfunction

function! s:get_current_branch() abort
  const l:branch = systemlist('git branch --show-current')[0]
  return l:branch
endfunction

function! s:get_current_commit_hash() abort
  const l:hash = systemlist('git rev-parse HEAD')[0]
  return l:hash
endfunction

function! s:normalize_linenumber(line1, line2) abort
  const l:head = '#'

  if a:line1 ==# a:line2
    return l:head .. 'L' .. string(a:line1)
  endif

  const l:line_separator = b:yank_remote_url_cache.type ==# 'gitlab' ? '-' : '+'
  return l:head .. 'L' .. string(a:line1) .. l:line_separator .. 'L' .. string(a:line2)
endfunction

function! s:find_git_root() abort
  let l:path = fnamemodify(expand('%'), ':p')
  while v:true
    if isdirectory(l:path .. '/.git')
      return l:path
    endif
    const l:modified = fnamemodify(l:path, ':h')
    if l:modified ==# l:path
      " is /
      return ''
    endif
    let l:path = l:modified
  endwhile
endfunction

function! s:yank(string) abort
  if exists('v:register')
    execute 'let' '@' .. v:register '=' string(a:string)
  else
    call s:echo_error('v:register is unknown')
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

" NOTE:
" GitHub: path/to/repo/blob/path/to/file#L1+L~
" GitLab: path/to/repo/~/blob/path/to/file#L1-L~
" GitBacket: path/to/repo/blob/path/to/file#L1+L~

function! yank_remote_url#generate_url(line1, ...) abort
  call s:init()
  if b:yank_remote_url_cache.git_root ==# ''
    return #{
          \ ok: v:false,
          \ err: 'It seems like not git directory.',
          \ }
  endif
  if b:yank_remote_url_cache.remote_url ==# ''
    return #{
          \ ok: v:false,
          \ err: 'It seems that this repository has no remote one.',
          \ }
  endif
  if b:yank_remote_url_cache.path ==# ''
    return #{
          \ ok: v:false,
          \ err: 'It seems untracked file.',
          \ }
    }
  endif

  let l:line1 = a:line1
  let l:line2 = a:0 ==# 0 ? a:line1 : a:1

  " make selectable line number in use command as <Cmd>~<CR>
  const l:another = line('v')
  if l:line1 == l:line2 && l:line1 != l:another
    if l:another < l:line1
      let l:line1 = l:another
    else
      let l:line2 = l:another
    endif
  endif

  const l:base_url = b:yank_remote_url_cache.remote_url
  const l:path_to_line = s:path_join(
        \ l:base_url,
        \ 'blob',
        \ get(g:, 'yank_remote_url#use_direct_hash', v:true)
        \   ? b:yank_remote_url_cache.current_hash
        \   : b:yank_remote_url_cache.current_branch,
        \ b:yank_remote_url_cache.path,
        \ ) .. s:normalize_linenumber(a:line1, l:line2)

  if get(g:, 'yank_remote_url#_debug', v:false)
    echomsg '[debug] cache is: ' .. string(b:yank_remote_url_cache)
  endif
  return #{
        \ ok: v:true,
        \ value: l:path_to_line,
        \ }
endfunction

function! yank_remote_url#yank_url(line1, ...) abort
  const l:line2 = a:0 ==# 0 ? a:line1 : a:1
  const l:res = yank_remote_url#generate_url(a:line1, l:line2)
  if !l:res.ok
    call s:echo_error(l:res.err)
    return
  endif
  call s:yank(l:res.value)
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo
