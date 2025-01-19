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
  const l:git_root = s:find_git_root(fnamemodify(expand('%'), ':p'))
  if !l:git_root.ok
    let b:yank_remote_url_cache = #{
          \ remote_url: '',
          \ current_branch: '',
          \ current_hash: '',
          \ path: '',
          \ }
    return
  endif
  const l:res = s:get_current_revision_info(l:git_root.value)
  if !l:res.ok
    let b:yank_remote_url_cache = #{
          \ remote_url: '',
          \ current_branch: '',
          \ current_hash: '',
          \ path: '',
          \ }
    return
  endif
  const l:url = s:get_remote_url(get(g:, 'yank_remote_url#remote_name', 'origin'))
  let b:yank_remote_url_cache = #{
        \ remote_url: s:normalize_url(l:url),
        \ current_branch: l:res.value.branch,
        \ current_hash: l:res.value.commit,
        \ git_root: l:git_root.value,
        \ path: expand('%')
        \       ->fnamemodify(':p')
        \       ->substitute('^' .. l:git_root.value, '', ''),
        \ }
endfunction

function s:is_current_file_tracked() abort
  if empty(b:yank_remote_url_cache.path)
    return v:false
  endif
  return v:true
endfunction

" is this ok for self-hosted?
const s:default_remote_separator_dict = {
      \ 'github.com': '+',
      \ 'gitlab': '-',
      \ 'gitbucket': '+',
      \ }

function! s:get_line_separator(url) abort
  for [regexp, separator] in items(get(g:, 'yank_remote_url#remote_separator_dict', s:default_remote_separator_dict))
    if a:url =~# regexp
      return separator
    endif
  endfor
  " NOTE: fallback '+'
  " Is it common?
  return '+'
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

function s:get_current_revision_info(git_root) abort
  const l:head_file = a:git_root .. '/.git/HEAD'
  if !filereadable(l:head_file)
    return #{
          \ ok: v:false,
          \ err: l:head_file .. ' file is not found.',
          \ }
  endif

  const l:head_content = readfile(l:head_file)->get(0, v:null)
  if l:head_content ==# v:null
    return #{
          \ ok: v:false,
          \ err: 'HEAD file is empty.',
          \ }
  endif
  if l:head_content !~ '^ref: '
    return #{
          \ ok: v:false,
          \ err: 'HEAD file is not ref: refs/heads/... format.',
          \ }
  endif
  const l:branch_name = l:head_content->substitute('^ref: refs/heads/', '', '')
  const l:commit_hash = readfile('.git/' .. substitute(l:head_content, '^ref: ', '', ''))->get(0, v:null)
  if l:commit_hash ==# v:null
    return #{
          \ ok: v:false,
          \ err: 'Commit hash is empty.',
          \ }
  endif
  return #{
        \ ok: v:true,
        \ value: #{
        \   branch: l:branch_name,
        \   commit: l:commit_hash,
        \ }
        \ }
endfunction

function! s:normalize_linenumber(line1, line2) abort
  const l:head = '#'

  if a:line1 ==# a:line2
    return l:head .. 'L' .. string(a:line1)
  endif
  const l:sep = s:get_line_separator(b:yank_remote_url_cache.remote_url)
  return l:head .. 'L' .. string(a:line1) .. l:sep  .. 'L' .. string(a:line2)
endfunction

function! s:find_git_root(start_path) abort
  let l:path = a:start_path
  while v:true
    if isdirectory(l:path .. '/.git')
      return #{
            \ ok: v:true,
            \ value: l:path,
            \ }
    endif
    let l:modified = fnamemodify(l:path, ':h')
    if l:modified ==# l:path
      " is /
      return #{
            \ ok: v:false,
            \ err: $'{start_path} is non git repository',
            \ }
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
