"=============================================================================
" a.vim --- plugin for manager alternate file
" Copyright (c) 2016-2019 Wang Shidong & Contributors
" Author: Wang Shidong < wsdjeg at 163.com >
" URL: https://spacevim.org
" License: GPLv3
"=============================================================================

let s:save_cpo = &cpo
set cpo&vim
scriptencoding utf-8


" Load SpaceVim API

let s:CMP = SpaceVim#api#import('vim#compatible')
let s:JSON = SpaceVim#api#import('data#json')
let s:FILE = SpaceVim#api#import('file')
let s:LOGGER =SpaceVim#logger#derive('a.vim')


" local value
"
" s:alternate_conf define which file should be loaded as alternate
" file configuration for current project, This is a directory
let s:alternate_conf = {
      \ '_' : '.project_alt.json'
      \ }
let s:cache_path = s:FILE.unify_path(g:spacevim_data_dir, ':p') . 'SpaceVim/a.json'


" this is for saving the project configuration information. Use the path of
" the project_alt.json file as the key.
let s:project_config = {}


" saving cache

function! s:cache() abort
  call writefile([s:JSON.json_encode(s:project_config)], s:FILE.unify_path(s:cache_path, ':p'))
endfunction

function! s:load_cache() abort
  call s:LOGGER.info('Try to load alt cache from: ' . s:cache_path)
  let cache_context = join(readfile(s:cache_path, ''), '')
  if !empty(cache_context)
    let s:project_config = s:JSON.json_decode(cache_context)
  endif
endfunction



" when this function is called, the project_config file name is changed, and
" the project_config info is cleared.
function! SpaceVim#plugins#a#set_config_name(path, name) abort
  let s:alternate_conf[a:path] = a:name
endfunction

function! s:get_project_config(conf_file) abort
  let conf = s:JSON.json_decode(join(readfile(a:conf_file), "\n"))
  let root = s:FILE.unify_path(a:conf_file, ':p:h')
  return {
        \ 'root' : root,
        \ 'config' : conf
        \ }
endfunction

function! SpaceVim#plugins#a#alt(request_paser,...) abort
  let type = get(a:000, 0, 'alternate')
  let conf_file_path = s:FILE.unify_path(get(s:alternate_conf, getcwd(), '_'), ':p')
  let file = s:FILE.unify_path(bufname('%'), ':.')
  let alt = SpaceVim#plugins#a#get_alt(file, conf_file_path, a:request_paser, type)
  if !empty(alt)
    exe 'e ' . alt
  else
    echo 'failed to find alternate file!'
  endif
endfunction


" the paser function should only accept one argv
" the alt_config_json
"
" @todo Rewrite alternate file paser
" paser function is written in vim script, and it is too slow,
" we are going to rewrite this function in other language.
" asynchronous paser should be supported.
function! s:paser(alt_config_json) abort
  call s:LOGGER.info('Start to paser alternate files for: ' . a:alt_config_json.root)
  let s:project_config[a:alt_config_json.root] = {}
  for key in keys(a:alt_config_json.config)
    let searchpath = key
    if match(searchpath, '/\*')
      let searchpath = substitute(searchpath, '*', '**/*', 'g')
    endif
    for file in s:CMP.globpath('.', searchpath)
      let file = s:FILE.unify_path(file, ':.')
      let s:project_config[a:alt_config_json.root][file] = {}
      if has_key(a:alt_config_json.config, file)
        for type in keys(a:alt_config_json.config[file])
          let s:project_config[a:alt_config_json.root][file][type] = a:alt_config_json.config[file][type]
        endfor
      else
        for type in keys(a:alt_config_json.config[key])
          let begin_end = split(key, '*')
          if len(begin_end) == 2
            let s:project_config[a:alt_config_json.root][file][type] =
                  \ s:get_type_path(
                  \ begin_end,
                  \ file,
                  \ a:alt_config_json.config[key][type]
                  \ )
          endif
        endfor
      endif
    endfor
  endfor
  call s:LOGGER.info('Paser done, try to cache alternate info')
  call s:cache()
endfunction

function! s:get_type_path(a, f, b) abort
  let begin_len = strlen(a:a[0])
  let end_len = strlen(a:a[1])
  "docs/*.md": {"alternate": "docs/cn/{}.md"},
  "begin_end = 5
  "end_len = 3
  "docs/index.md
  return substitute(a:b, '{}', a:f[begin_len : (end_len+1) * -1], 'g')
endfunction

function! s:is_config_changed(conf_path) abort
  if getftime(a:conf_path) > getftime(s:cache_path)
    call s:LOGGER.info('alt config file ('
          \ . a:conf_path
          \ . ') has been changed, paser required!')
    return 1
  endif
endfunction

function! SpaceVim#plugins#a#get_alt(file, conf_path, request_paser,...) abort
  call s:LOGGER.info('getting alt file for:' . a:file)
  call s:LOGGER.info('  >   type: ' . get(a:000, 0, 'alternate'))
  call s:LOGGER.info('  >  paser: ' . a:request_paser)
  call s:LOGGER.info('  > config: ' . a:conf_path)
  " @question when should the cache be loaded?
  " if the local value s:project_config do not has the key a:conf_path
  " and the file a:conf_path has not been updated since last cache
  " and no request_paser specified
  let alt_config_json = s:get_project_config(a:conf_path)
  if !has_key(s:project_config, alt_config_json.root)
        \ && !s:is_config_changed(a:conf_path)
        \ && !a:request_paser
    " config file has been cached since last update.
    " so no need to paser the config for current config file
    " just load the cache
    call s:load_cache()
    if !has_key(s:project_config, alt_config_json.root)
          \ || !has_key(s:project_config[alt_config_json.root], a:file)
      call s:paser(alt_config_json)
    endif
  else
    call s:paser(alt_config_json)
  endif
  try
    return s:project_config[alt_config_json.root][a:file][get(a:000, 0, 'alternate')]
  catch
    return ''
  endtry
endfunction

function! s:get_alternate(file) abort

endfunction


function! SpaceVim#plugins#a#getConfigPath() abort
  return s:FILE.unify_path(get(s:alternate_conf, getcwd(), '_'), ':p')
endfunction

function! SpaceVim#plugins#a#complete(ArgLead, CmdLine, CursorPos) abort
  let file = s:FILE.unify_path(bufname('%'), ':.')
  let conf_file_path = s:FILE.unify_path(get(s:alternate_conf, getcwd(), '_'), ':p')
  let alt_config_json = s:get_project_config(conf_file_path)

  call SpaceVim#plugins#a#get_alt(file, conf_file_path, 0)
  try
    let a = s:project_config[alt_config_json.root][file]
  catch
    let a = {}
  endtry
  return join(keys(a), "\n")
endfunction

let &cpo = s:save_cpo
unlet s:save_cpo

" vim:set et sw=2 cc=80:
