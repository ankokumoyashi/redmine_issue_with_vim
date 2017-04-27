let s:redmine_server = get(g:, 'metarw_redmine_server')
let s:redmine_apikey = get(g:, 'metarw_redmine_apikey')
let s:want_content = 0
function! metarw#redmine#read(fakepath)
    echomsg string("read")
    let _ = s:parse_incomplete_fakepath(a:fakepath)
    echomsg string(s:want_content)
    if !s:want_content
      let result = s:read_list(_)
      let s:want_content = 1
    else
      let result = s:read_content(_)
      echomsg string(result)
      echomsg string("aaaa")
    endif
    echomsg string(result)
    return result
endfunction

function! metarw#redmine#write(fakepath, line1, line2, append_p)
  echomsg string('metarw#redmine#write')
  let _ = s:parse_incomplete_fakepath(a:fakepath)
  echomsg string(a:line1-1)
  echomsg string(a:line2)
  let content = join(getline(a:line1, a:line2), "\n")
  echomsg string(content)
  if !_.project_given_p && !_.issue_given_p
    echoerr 'Unexpected a:incomplete_fakepath:' string(a:incomplete_fakepath)
    throw 'metarw:redmine#e1'
  elseif !_.issue_given_p
    let result = s:write_new(_, content)
    if result[0] != 'error'
    endif
  else
    let result = s:write_update(_, content)
  endif

  return result
endfunction


function! s:parse_incomplete_fakepath(incomplete_fakepath)
  echomsg string('s:parse_incomplete_fakepath')
  let _ = {}
  let fragments = split(a:incomplete_fakepath, '^\l\+\zs:', !0)
"'redmine:'
  echomsg string(a:incomplete_fakepath)
"['redmine', '']
  echomsg string(fragments)
  " :が入ってなかったりしたらここでargumentを検定している
  if len(fragments) <= 1
    echoerr 'Unexpected a:incomplete_fakepath:' string(a:incomplete_fakepath)
    throw 'metarw:redmine#e1'
  endif
  let fragments = [fragments[0]] + split(fragments[1], '[\/]')
  "["redmine"]
  echomsg string(fragments)

  "辞書に要素を代入する時はこうする
  let _.given_fakepath = a:incomplete_fakepath
  let _.scheme = fragments[0]

  " {project}
  let i = 1
  if i < len(fragments)
    let _.project_given_p = !0
    let _.project = fragments[i]
    let i += 1
  else
    let _.project_given_p = !!0
    let _.project = ''
  endif

  " {issue}
  if i < len(fragments)
    let _.issue_given_p = !0
    let _.issue = fragments[i]
    let i += 1
  else
    let _.issue_given_p = !!0
    let _.issue = ''
  endif

  return _
endfunction

function! s:format(issue)
  echomsg string('s:format')
  let content = []
  for [k, v] in items(a:issue)
    if k != 'description'
      if type(v) == 4 && has_key(v, 'id')
        call add(content, printf("%s: %s", k, v.id))
      else
        call add(content, printf("%s: %s", k, iconv(webapi#json#encode(v), 'utf-8', &encoding)))
      endif
    endif
    unlet v
  endfor
  call add(content, '--')
  let description = has_key(a:issue, 'description') ? substitute(a:issue.description, "\r", "", "g") : ''
  let content += split(description, "\n")
  echomsg string(content)
  return content
endfunction

function! s:read_content(_)
  echomsg string('s:read_content')
  let issue = s:get_issue(a:_)
  echomsg string(s:format(issue))
  call setline(1, s:format(issue))

  return ['done', '']
endfunction

function! s:read_list(_)
  let result = []
  let issues = s:get_issues(a:_)
  for issue in issues
      if issue["project"]["id"] == 27
          call add(result, {
          \    'label': issue.subject,
          \    'fakepath': printf('%s:/issues/%s',
          \                       a:_.scheme,
          \                       issue.id)
          \ })
      endif
  endfor
  return ['browse',result]
endfunction


function! s:write_new(_, content)
  echomsg string('s:write_new')
  echomsg string(a:_)
  echomsg string(a:content)
  let data = {}
  let lines = split(a:content, '\n--\n', 2)
  if len(lines) < 2
    let metadata = ''
    let body = a:content
  else
    let metadata = lines[0]
    let body = lines[1]
  endif
  for line in split(metadata, "\n")
    let pos = stridx(line, ':')
    if pos > 0
      let data[line[0:pos-1]] = webapi#json#decode(line[pos+1:])
    endif
  endfor
  if !has_key(data, 'subject')
    let data['subject'] = split(body, "\n", 1)[0]
  endif
  let data['description'] = body
  let data['project_id'] = a:_.project
  let result = webapi#http#post(s:url('/issues.json'),
  \ webapi#json#encode({"issue": data}), {
  \   "Content-Type": "application/json"
  \ })
  if split(result.header[0])[1] != '201'
    return ['error', result.header[0]]
  endif
  let data = webapi#json#decode(result.content).issue
  exe 'noau file' printf('redmine:/%s/%s', data.project.id, data.id)
  silent! %d _
  call setline(1, s:format(data))

  setlocal nomodified

  return ['done', '']
endfunction


function! s:write_update(_, content)
  echomsg string('s:write_update')
  let data = {}
  let lines = split(a:content, '\n--\n', 2)
  echomsg string(lines)
  if len(lines) < 2
    let metadata = ''
    let body = a:content
  else
    let metadata = lines[0]
    let body = lines[1]
  endif
  for line in split(metadata, "\n")
    let pos = stridx(line, ':')
    if pos > 0
      let data[line[0:pos-1]] = webapi#json#decode(line[pos+1:])
      echomsg string(line[pos+1:])
      echomsg string(webapi#json#decode(line[pos+1:]))
    endif
  endfor
  echomsg string(data)
  echomsg string(body)
  if !has_key(data, 'subject')
    let data['subject'] = split(body, "\n", 1)[0]
  endif
  let data['description'] = body
  let data['project_id'] = a:_.project
  let result = webapi#http#post(s:url('/issues/', a:_.issue, '.json'),
  \ webapi#json#encode({"issue": data}), {
  \   "Content-Type": "application/json"
  \ }, 'PUT')
  if result.status !~ '^2'
    return ['error', result.message]
  endif
  echomsg string(result)

  return ['done', '']
endfunction

function! s:get_projects(_)
  echomsg string('s:get_projects')
  let result = webapi#http#get(s:url('/projects.json'), '', {
  \   "Content-Type": "application/json"
  \ })
  if result.status !~ '^2'
    throw result.message
  endif

  let json = webapi#json#decode(result.content)
  if type(json) != 3 && has_key(json, 'errors')
    throw json.error
  endif

  return json.projects
endfunction

function! s:url(...)
  echomsg string('s:url')
  echomsg string(a:000)
  let server = substitute(s:redmine_server, '/\+$', '', '')
  return join([server] + a:000 + ['?key=', s:redmine_apikey], '')
endfunction

function! s:get_issues(_)
  echomsg string('s:get_issues')
  let result = webapi#http#get(s:url('/issues.json'), '', {
  \   "Content-Type": "application/json"
  \ })
  if result.status !~ '^2'
    return ['error', result.message]
  endif

  let json = webapi#json#decode(result.content)
  if type(json) != 3 && has_key(json, 'errors')
    throw json.error
  endif

  return json.issues
endfunction

function! s:get_issue(_)
  echomsg string('s:get_issue')

  let result = webapi#http#get(s:url('/issues/', a:_.issue, '.json'), '', {
  \   "Content-Type": "application/json"
  \ })
  if result.status !~ '^2'
    return ['error', result.message]
  endif

  let json = webapi#json#decode(result.content)
  if type(json) != 3 && has_key(json, 'errors')
    throw json.error
  endif

  return json.issue
endfunction
