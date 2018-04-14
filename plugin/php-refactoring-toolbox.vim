"
" VIM PHP Refactoring Toolbox
"
" Maintainer: Pierrick Charron <pierrick@adoy.net>
" URL: https://github.com/adoy/vim-php-refactoring-toolbox
" License: MIT
" Version: 1.0.3
"

if exists('g:vim_php_refactoring_loaded')
    finish
endif
let g:vim_php_refactoring_loaded = 1

" Config {{{
" VIM function to call to document the current line
if !exists('g:vim_php_refactoring_phpdoc')
    let g:vim_php_refactoring_phpdoc = 'PhpDoc'
endif

if !exists('g:vim_php_refactoring_use_default_mapping')
    let g:vim_php_refactoring_use_default_mapping = 1
endif

if !exists('g:vim_php_refactoring_auto_validate')
    let g:vim_php_refactoring_auto_validate = 0
endif

if !exists('g:vim_php_refactoring_auto_validate_sg')
    let g:vim_php_refactoring_auto_validate_sg = g:vim_php_refactoring_auto_validate
endif

if !exists('g:vim_php_refactoring_auto_validate_g')
    let g:vim_php_refactoring_auto_validate_g = g:vim_php_refactoring_auto_validate
endif

if !exists('g:vim_php_refactoring_auto_validate_rename')
    let g:vim_php_refactoring_auto_validate_rename = g:vim_php_refactoring_auto_validate
endif

if !exists('g:vim_php_refactoring_auto_validate_visibility')
    let g:vim_php_refactoring_auto_validate_visibility = g:vim_php_refactoring_auto_validate
endif

if !exists('g:vim_php_refactoring_default_property_visibility')
    let g:vim_php_refactoring_default_property_visibility = 'private'
endif

if !exists('g:vim_php_refactoring_default_method_visibility')
    let g:vim_php_refactoring_default_method_visibility = 'private'
endif

if !exists('g:vim_php_refactoring_make_setter_fluent')
    let g:vim_php_refactoring_make_setter_fluent = 0
endif
" }}}

" Refactoring mapping {{{
if g:vim_php_refactoring_use_default_mapping == 1
    nnoremap <unique> <Leader>pr :call PhpRename()<CR>
    nnoremap <unique> <Leader>pi :call PhpInline()<CR>
    nnoremap <unique> <Leader>rlv :call PhpRenameLocalVariable()<CR>
    nnoremap <unique> <Leader>rcv :call PhpRenameClassVariable()<CR>
    nnoremap <unique> <Leader>rcc :call PhpRenameClassConstant()<CR>
    nnoremap <unique> <Leader>rm :call PhpRenameMethod()<CR>
    nnoremap <unique> <Leader>eu :call PhpExtractUse()<CR>
    vnoremap <unique> <Leader>ec :call PhpExtractConst()<CR>
    nnoremap <unique> <Leader>ep :call PhpExtractClassProperty()<CR>
    vnoremap <unique> <Leader>em :call PhpExtractMethod()<CR>
    nnoremap <unique> <Leader>np :call PhpCreateProperty()<CR>
    nnoremap <unique> <Leader>du :call PhpDetectUnusedUseStatements()<CR>
    vnoremap <unique> <Leader>== :call PhpAlignAssigns()<CR>
    nnoremap <unique> <Leader>sg :call PhpCreateSettersAndGetters()<CR>
    nnoremap <unique> <Leader>cog :call PhpCreateGetters()<CR>
    nnoremap <unique> <Leader>da :call PhpDocAll()<CR>
endif
" }}}

" +--------------------------------------------------------------+
" |   VIM REGEXP REMINDER   |    Vim Regex       |   Perl Regex   |
" |===============================================================|
" | Vim non catchable       | \%(.\)             | (?:.)          |
" | Vim negative lookahead  | Start\(Date\)\@!   | Start(?!Date)  |
" | Vim positive lookahead  | Start\(Date\)\@=   | Start(?=Date)  |
" | Vim negative lookbehind | \(Start\)\@<!Date  | (?<!Start)Date |
" | Vim positive lookbehind | \(Start\)\@<=Date  | (?<=Start)Date |
" | Multiline search        | \_s\_.             | \s\. multiline |
" +--------------------------------------------------------------+

" Regex defintion {{{
let s:php_regex_phptag_line = '<?\%(php\)\?'
let s:php_regex_ns_line     = '^namespace\_s\+[\\_A-Za-z0-9]*\_s*[;{]'
let s:php_regex_use_line    = '^use\_s\+[\\_A-Za-z0-9]\+\%(\_s\+as\_s\+[_A-Za-z0-9]\+\)\?\_s*\%(,\_s\+[\\_A-Za-z0-9]\+\%(\_s\+as\_s\+[_A-Za-z0-9]\+\)\?\_s*\)*;'
let s:php_regex_class_line  = '^\%(\%(final\s\+\|abstract\s\+\)\?class\>\|trait\>\)'
let s:php_regex_const_line  = '^\s*const\s\+[^;]\+;'
let s:php_regex_member_line = '^\s*\%(\%(private\|protected\|public\|static\)\s*\)\+\$'
let s:php_regex_func_line   = '^\s*\%(\%(private\|protected\|public\|static\|abstract\)\s*\)*function\_s\+'

let s:php_regex_local_var   = '\$\<\%(this\>\)\@![A-Za-z0-9]*'
let s:php_regex_assignment  = '+=\|-=\|*=\|/=\|=\~\|!=\|='
let s:php_regex_fqcn        = '[\\_A-Za-z0-9]*'
let s:php_regex_cn          = '[_A-Za-z0-9]\+'
" }}}

" Fluent {{{
let s:php_fluent_this = "keepjumps normal! jo\<CR>return $this;"
" }}}

" Enum of the different types of expression
let s:t_variable  = 0
let s:t_function  = 1
let s:t_method    = 2
let s:t_attribute = 3
let s:t_constant  = 4
let s:t_unknown   = -1

function! PhpDocAll() " {{{
    call s:SaveView()

    if exists("*" . g:vim_php_refactoring_phpdoc) == 0
        call s:PhpEchoError(g:vim_php_refactoring_phpdoc . '() vim function doesn''t exists.')
        return
    endif
    keepjumps normal! gg
    while search(s:php_regex_class_line, 'eW') > 0
        call s:PhpDocument()
    endwhile
    keepjumps normal! gg
    while search(s:php_regex_member_line, 'eW') > 0
        call s:PhpDocument()
    endwhile
    keepjumps normal! gg
    while search(s:php_regex_func_line, 'eW') > 0
        call s:PhpDocument()
    endwhile

    call s:ResetView()
endfunction
" }}}

function! PhpCreateGetters() " {{{
    keepjumps normal! gg
    let l:properties = []
    while search(s:php_regex_member_line, 'eW') > 0
        normal! w"xye
        call add(l:properties, @x)
    endwhile
    for l:property in l:properties
        let l:camelCaseName = substitute(l:property, '^_\?\(.\)', '\U\1', '')
        if g:vim_php_refactoring_auto_validate_g == 0
            call s:PhpEchoError('Create get' . l:camelCaseName . '()')
            if inputlist(["0. No", "1. Yes"]) == 0
                continue
            endif
        endif
        if search(s:php_regex_func_line . "get" . l:camelCaseName . '\>', 'n') == 0
            call s:PhpInsertMethod("public", "get" . l:camelCaseName, [], "return $this->" . l:property . ";\n")
        endif
    endfor
endfunction
" }}}

function! PhpCreateSettersAndGetters() " {{{
    keepjumps normal! gg
    let l:properties = []
    while search(s:php_regex_member_line, 'eW') > 0
        normal! w"xye
        call add(l:properties, @x)
    endwhile
    for l:property in l:properties
        let l:camelCaseName = substitute(l:property, '^_\?\(.\)', '\U\1', '')
        if g:vim_php_refactoring_auto_validate_sg == 0
            call s:PhpEchoError('Create set' . l:camelCaseName . '() and get' . l:camelCaseName . '()')
            if inputlist(["0. No", "1. Yes"]) == 0
                continue
            endif
        endif
        if search(s:php_regex_func_line . "set" . l:camelCaseName . '\>', 'n') == 0
            call s:PhpInsertMethod("public", "set" . l:camelCaseName, ['$' . substitute(l:property, '^_', '', '') ], "$this->" . l:property . " = $" . substitute(l:property, '^_', '', '') . ";\n")
            if g:vim_php_refactoring_make_setter_fluent > 0
                call s:PhpInsertFluent()
            endif
        endif
        if search(s:php_regex_func_line . "get" . l:camelCaseName . '\>', 'n') == 0
            call s:PhpInsertMethod("public", "get" . l:camelCaseName, [], "return $this->" . l:property . ";\n")
        endif
    endfor
endfunction
" }}}

function! PhpRename() " {{{
    let l:type = s:PhpIdentityExpressionType('.', expand('<cword>'))

    if l:type == s:t_method
      call PhpRenameMethod()
    elseif l:type == s:t_attribute
      call PhpRenameClassVariable()
    elseif l:type == s:t_constant
      call PhpRenameClassConstant()
    elseif l:type == s:t_function
      " TODO
      "call PhpRenameFunction()
    elseif l:type == s:t_variable
      call PhpRenameLocalVariable()
    endif
endfunction
" }}}

function! PhpRenameLocalVariable() " {{{
    let l:oldName = substitute(expand('<cword>'), '^\$*', '', '')
    let l:newName = inputdialog('Rename ' . l:oldName . ' to: ')
    if g:vim_php_refactoring_auto_validate_rename == 0
        if s:PhpSearchInCurrentFunction('\C$' . l:newName . '\>', 'n') > 0
            call s:PhpEchoError('$' . l:newName . ' seems to already exist in the current function scope. Rename anyway ?')
            if inputlist(["0. No", "1. Yes"]) == 0
                return
            endif
        endif
    endif
    call s:PhpReplaceInCurrentFunction('\C$' . l:oldName . '\>', '$' . l:newName)
endfunction
" }}}

function! PhpRenameClassVariable() " {{{
    let l:pattern = '\C\%(\%(\%(public\|protected\|private\|static\)\_s\+\)\+\$\|$this->\|self::\$\|static::\$\)\@<='
    let l:oldName = substitute(expand('<cword>'), '^\$*', '', '')

    call s:RenameInCurrentClass(l:oldName, l:pattern)
endfunction
" }}}

function! PhpRenameClassConstant() " {{{
    let l:pattern = '\%(\%(\%(public\|protected\|private\)\s\+\)\?const\s\+\|\%(self\|static\)::\)\zs'
    let l:oldName = expand('<cword>')

    call s:RenameInCurrentClass(l:oldName, l:pattern)
endfunction
" }}}

function! PhpRenameMethod() " {{{
    let l:pattern = '\%(\%(' . s:php_regex_func_line . '\)\|$this->\)\@<='
    let l:oldName = substitute(expand('<cword>'), '^\$*', '', '')

    call s:RenameInCurrentClass(l:oldName, l:pattern)
endfunction
" }}}

function! PhpExtractUse() " {{{
    call s:SaveView()

    let l:fqcn = s:PhpGetFQCNUnderCursor()
    let l:use  = s:PhpGetDefaultUse(l:fqcn)
    let l:defaultUse = l:use
    if strlen(use) == 0
        let defaultUse = s:PhpGetShortClassName(l:fqcn)
    endif

    " Use negative lookahead and behind to make sure we don't replace exact string
    exec ':%s/\%([''"]\)\@<!' . substitute(l:fqcn, '[\\]', '\\\\', 'g') . '\%([''"]\)\@!/' . l:defaultUse . '/ge'
    if strlen(l:use)
        call s:PhpInsertUseStatement(l:fqcn . ' as ' . l:use)
    else
        call s:PhpInsertUseStatement(l:fqcn)
    endif

    call s:ResetView()
endfunction
" }}}

function! PhpExtractConst() " {{{
    if visualmode() != 'v'
        call s:PhpEchoError('Extract constant only works in Visual mode, not in Visual Line or Visual block')
        return
    endif
    call s:SaveView()

    let l:name = toupper(inputdialog("Name of new const: "))
    normal! gv"xy
    call s:PhpReplaceInCurrentClass('\V' . escape(@x, '\\/'), 'self::' . l:name)
    call s:PhpInsertConst(l:name, @x)

    call s:ResetView()
endfunction
" }}}

function! PhpExtractClassProperty() " {{{
    call s:SaveView()

    let l:name = substitute(expand('<cword>'), '^\$*', '', '')
    call s:PhpReplaceInCurrentFunction('$' . l:name . '\>', '$this->' . l:name)
    if g:vim_php_refactoring_auto_validate_visibility == 0
        let l:visibility = inputdialog("Visibility (default is " . g:vim_php_refactoring_default_property_visibility . "): ")
        if empty(l:visibility)
            let l:visibility =  g:vim_php_refactoring_default_property_visibility
        endif
    else
        let l:visibility =  g:vim_php_refactoring_default_property_visibility
    endif
    call s:PhpInsertProperty(l:name, l:visibility)

    call s:ResetView()
endfunction
" }}}

function! PhpExtractMethod() range " {{{
    if visualmode() == ''
        call s:PhpEchoError('Extract method doesn''t works in Visual Block mode. Use Visual line or Visual mode.')
        return
    endif
    let l:name = inputdialog("Name of new method: ")
    if g:vim_php_refactoring_auto_validate_visibility == 0
        let l:visibility = inputdialog("Visibility (default is " . g:vim_php_refactoring_default_method_visibility . "): ")
        if empty(l:visibility)
            let l:visibility =  g:vim_php_refactoring_default_method_visibility
        endif
    else
        let l:visibility =  g:vim_php_refactoring_default_method_visibility
    endif
    normal! gv"xd
    let l:middleLine = line('.')
    call search(s:php_regex_func_line, 'bW')
    let l:startLine = line('.')
    call search('(', 'W')
    normal! "pyi(
    call search('{', 'W')
    exec "keepjumps normal! %"
    let l:stopLine = line('.')
    let l:beforeExtract = join(getline(l:startLine, l:middleLine-1))
    let l:afterExtract  = join(getline(l:middleLine, l:stopLine))
    let l:parameters = []
    let l:parametersSignature = []
    let l:output = []
    for l:var in s:PhpMatchAllStr(@x, s:php_regex_local_var)
        if match(l:beforeExtract, l:var . '\>') > 0
            call add(l:parameters, l:var)
            if @p =~ '[^,]*' . l:var . '\>[^,]*'
                call add(l:parametersSignature, substitute(matchstr(@p, '[^,]*' . l:var . '\>[^,]*'), '^\s*\(.\{-}\)\s*$', '\1', 'g'))
            else
                call add(l:parametersSignature, l:var)
            endif
        endif
        if match(l:afterExtract, l:var . '\>') > 0
            call add(l:output, l:var)
        endif
    endfor
    call s:SaveView()

    if len(l:output) == 0
        exec "normal! O$this->" . l:name . "(" . join(l:parameters, ", ") . ");\<ESC>k=3="
        let l:return = ''
    elseif len(l:output) == 1
        exec "normal! O" . l:output[0] . " = $this->" . l:name . "(" . join(l:parameters, ", ") . ");\<ESC>=3="
        let l:return = "return " . l:output[0] . ";\<CR>"
    else
        exec "normal! Olist(" . join(l:output, ", ") . ") = $this->" . l:name . "(" . join(l:parameters, ", ") . ");\<ESC>=3="
        let l:return = "return array(" . join(l:output, ", ") . ");\<CR>"
    endif
    call s:PhpInsertMethod(l:visibility, l:name, l:parametersSignature, @x . l:return)

    call s:ResetView()
endfunction
" }}}

function! PhpCreateProperty() " {{{
    let l:name = inputdialog("Name of new property: ")
    if g:vim_php_refactoring_auto_validate_visibility == 0
        let l:visibility = inputdialog("Visibility (default is " . g:vim_php_refactoring_default_property_visibility . "): ")
        if empty(l:visibility)
            let l:visibility =  g:vim_php_refactoring_default_property_visibility
        endif
    else
        let l:visibility =  g:vim_php_refactoring_default_property_visibility
    endif
    call s:PhpInsertProperty(l:name, l:visibility)
endfunction
" }}}

function! PhpDetectUnusedUseStatements() " {{{
    call s:SaveView()

    keepjumps normal! gg
    while search('^use', 'W')
        let l:startLine = line('.')
        call search(';\_s*', 'eW')
        let l:endLine = line('.')
        let l:line = join(getline(l:startLine, l:endLine))
        for l:useStatement in split(substitute(l:line, '^\%(use\)\?\s*\([^;]*\);', '\1', ''), ',')
            let l:matches = matchlist(l:useStatement, '\s*\\\?\%([_A-Za-z0-9]\+\\\)*\([_A-Za-z0-9]\+\)\%(\s*as\s*\([_A-Za-z0-9]\+\)\)\?')
            let l:alias = s:PhpPopList(l:matches)
            if search(l:alias, 'nW') == 0
                echo 'Unused: ' . l:useStatement
            endif
        endfor
    endwhile

    call s:ResetView()
endfunction
" }}}

function! PhpAlignAssigns() range " {{{
" This funcion was took from :
" Vim refactoring plugin
" Maintainer: Eustaquio 'TaQ' Rangel
" License: GPL
" URL: git://github.com/taq/vim-refact.git
    let l:max   = 0
    let l:maxo  = 0
    let l:linc  = ""
    for l:line in range(a:firstline,a:lastline)
        let l:linc  = getbufline("%", l:line)[0]
        let l:rst   = match(l:linc, '\%(' . s:php_regex_assignment . '\)')
        if l:rst < 0
            continue
        endif
        let l:rstl  = matchstr(l:linc, '\%(' . s:php_regex_assignment . '\)')
        let l:max   = max([l:max, strlen(substitute(strpart(l:linc, 0, l:rst), '\s*$', '', '')) + 1])
        let l:maxo  = max([l:maxo, strlen(l:rstl)])
    endfor
    let l:formatter= '\=printf("%-'.l:max.'s%-'.l:maxo.'s%s",submatch(1),submatch(2),submatch(3))'
    let l:expr     = '^\(.\{-}\)\s*\('.s:php_regex_assignment.'\)\(.*\)'
    for l:line in range(a:firstline,a:lastline)
        let l:oldline = getbufline("%",l:line)[0]
        let l:newline = substitute(l:oldline,l:expr,l:formatter,"")
        call setline(l:line,l:newline)
    endfor
endfunction
" }}}

" Inlines an assignation
function! PhpInline() " {{{
    let l:matches = matchlist(getline('.'), '\v^\s*\$(\w+)>\s*\=\s*(.+);$')
    if empty(l:matches)
        return
    endif

    call s:SaveView()
    " If the next line is empty and the previous one is either ending with {
    " (new bloc) or empty as well, then we delete the next line too
    let l:previous_line = getline(line('.') - 1)
    if getline(line('.') + 1) =~ '^\s*$' &&
          \ (l:previous_line =~ '{\s*$' || l:previous_line =~ '^\s*$')
        delete _ 2
    else
        delete _
    endif

    call s:PhpReplaceInCurrentFunction('\v\$' . l:matches[1]. '>', l:matches[2])
    call s:ResetView()
endfunction
" }}}

function! s:PhpDocument() " {{{
    if match(getline(line('.')-1), "*/") == -1
        exec "call " . g:vim_php_refactoring_phpdoc . '()'
    endif
endfunction
" }}}

function! s:PhpReplaceInCurrentFunction(search, replace) " {{{
    call s:SaveView()

    call search(s:php_regex_func_line, 'bW')
    let l:startLine = line('.')
    call search('{', 'W')
    exec "keepjumps normal! %"
    let l:stopLine = line('.')
    exec l:startLine . ',' . l:stopLine . ':s/' . a:search . '/'. a:replace .'/ge'

    call s:ResetView()
endfunction
" }}}

function! s:RenameInCurrentClass(oldName, pattern) " {{{
    let l:newName = inputdialog('Rename ' . a:oldName . ' to: ')
    if g:vim_php_refactoring_auto_validate_rename == 0 &&
          \s:PhpSearchInCurrentClass(a:pattern . l:newName . '\>', 'n') > 0
        call s:PhpEchoError(l:newName . ' seems to already exist in the current class. Rename anyway ?')
        if inputlist(["0. No", "1. Yes"]) == 0
            return
        endif
    endif

    call s:PhpReplaceInCurrentClass(a:pattern . a:oldName . '\>', l:newName)
endfunction
" }}}

function! s:PhpReplaceInCurrentClass(search, replace) " {{{
    call s:SaveView()

    call search(s:php_regex_class_line, 'beW')
    call search('{', 'W')
    let l:startLine = line('.')
    exec "keepjumps normal! %"
    let l:stopLine = line('.')
    exec l:startLine . ',' . l:stopLine . ':s/' . a:search . '/'. a:replace .'/ge'

    call s:ResetView()
endfunction
" }}}

function! s:PhpInsertUseStatement(use) " {{{
    let l:use = 'use ' . substitute(a:use, '^\\', '', '') . ';'
    if search(s:php_regex_use_line, 'beW') > 0
        call append(line('.'), l:use)
    elseif search(s:php_regex_ns_line, 'beW') > 0
        call append(line('.'), '')
        call append(line('.')+1, l:use)
    elseif search(s:php_regex_phptag_line, 'beW') > 0
        call append(line('.'), '')
        call append(line('.')+1, l:use)
    else
        call append(1, l:use)
    endif
endfunction
" }}}

function! s:PhpInsertConst(name, value) " {{{
    if search(s:php_regex_const_line, 'beW') > 0
        call append(line('.'), 'const ' . a:name . ' = ' . a:value . ';')
    elseif search(s:php_regex_class_line, 'beW') > 0
        call search('{', 'W')
        call append(line('.'), 'const ' . a:name . ' = ' . a:value . ';')
        call append(line('.')+1, '')
    else
        call append(line('.'), 'const ' . a:name . ' = ' . a:value . ';')
    endif
    normal! j=1=
endfunction
" }}}

function! s:PhpInsertProperty(name, visibility) " {{{
    let l:regex = '\%(' . join([s:php_regex_member_line, s:php_regex_const_line, s:php_regex_class_line], '\)\|\(') .'\)'
    if search(l:regex, 'beW') > 0
        let l:line = getbufline("%", line('.'))[0]
        if match(l:line, s:php_regex_class_line) > -1
            call search('{', 'W')
            call s:PhpInsertPropertyExtended(a:name, a:visibility, line('.'), 0)
        else
            call search(';', 'W')
            call s:PhpInsertPropertyExtended(a:name, a:visibility, line('.'), 1)
        endif
    else
        call search(';', 'W')
        call s:PhpInsertPropertyExtended(a:name, a:visibility, line('.'), 0)
    endif
endfunction
" }}}

function! s:PhpInsertPropertyExtended(name, visibility, insertLine, emptyLineBefore) " {{{
    call append(a:insertLine, '')
    call append(a:insertLine + a:emptyLineBefore, '/**')
    call append(a:insertLine + a:emptyLineBefore + 1, '* @var mixed')
    call append(a:insertLine + a:emptyLineBefore + 2, '*/')
    call append(a:insertLine + a:emptyLineBefore + 3, a:visibility . " $" . a:name . ';')
    normal! j=5=
endfunction
" }}}

function! s:PhpInsertMethod(modifiers, name, params, impl) " {{{
    call search(s:php_regex_func_line, 'beW')
    call search('{', 'W')
    exec "keepjumps normal! %"
    exec "normal! o\<CR>" . a:modifiers . " function " . a:name . "(" . join(a:params, ", ") . ")\<CR>{\<CR>" . a:impl . "}\<Esc>=a{"
endfunction
" }}}

function! s:PhpGetFQCNUnderCursor() " {{{
    let l:line = getbufline("%", line('.'))[0]
    let l:lineStart = strpart(l:line, 0, col('.'))
    let l:lineEnd   = strpart(l:line, col('.'), strlen(l:line) - col('.'))
    return matchstr(l:lineStart, s:php_regex_fqcn . '$') . matchstr(l:lineEnd, '^' . s:php_regex_cn)
endfunction
" }}}

function! s:PhpGetShortClassName(fqcn) " {{{
    return matchstr(a:fqcn, s:php_regex_cn . '$')
endfunction
" }}}

function! s:PhpGetDefaultUse(fqcn) " {{{
    return inputdialog("Use as [Default: " . s:PhpGetShortClassName(a:fqcn) ."] : ")
endfunction
" }}}

function! s:PhpPopList(list) " {{{
    for l:elem in reverse(a:list)
        if strlen(l:elem) > 0
            return l:elem
        endif
    endfor
endfunction
" }}}

function! s:PhpSearchInCurrentFunction(pattern, flags) " {{{
    call s:SaveView()

    call search(s:php_regex_func_line, 'bW')
    let l:startLine = line('.')
    call search('{', 'W')
    exec "keepjumps normal! %"
    let l:stopLine = line('.')

    call s:ResetView()
    return s:PhpSearchInRange(a:pattern, a:flags, l:startLine, l:stopLine)
endfunction
" }}}

function! s:PhpSearchInCurrentClass(pattern, flags) " {{{
    call s:SaveView()

    call search(s:php_regex_class_line, 'beW')
    call search('{', 'W')
    let l:startLine = line('.')
    exec "keepjumps normal! %"
    let l:stopLine = line('.')

    call s:ResetView()
    return s:PhpSearchInRange(a:pattern, a:flags, l:startLine, l:stopLine)
endfunction
" }}}

function! s:PhpSearchInRange(pattern, flags, startLine, endLine) " {{{
    return search('\%>' . a:startLine . 'l\%<' . a:endLine . 'l' . a:pattern, a:flags)
endfunction
" }}}

function! s:PhpMatchAllStr(haystack, needle) " {{{
    let l:result = []
    let l:matchPos = match(a:haystack, a:needle, 0)
    while l:matchPos > 0
        let l:str      = matchstr(a:haystack, a:needle, l:matchPos)
        if index(l:result, l:str) < 0
            call add(l:result, l:str)
        endif
        let l:matchPos = match(a:haystack, a:needle, l:matchPos + strlen(l:str))
    endwhile
    return l:result
endfunction
" }}}

function! s:PhpEchoError(message) " {{{
    echohl ErrorMsg
    echomsg a:message
    echohl NONE
endfunction
" }}}

function! s:PhpInsertFluent() " {{{
    if g:vim_php_refactoring_make_setter_fluent == 1
        exec s:php_fluent_this
    elseif g:vim_php_refactoring_make_setter_fluent == 2
        call s:PhpEchoError('Make fluent?')
        if inputlist(["0. No", "1. Yes"]) == 1
            exec s:php_fluent_this
        endif
    else
        echoerr 'Invalid option for g:vim_php_refactoring_make_setter_fluent'
    endif
endfunction
" }}}

function! s:PhpIdentityExpressionType(line, word) " {{{
    let l:line = getline(a:line)

    " Names things to be clearer
    let l:visibility = '%(public|protected|private)\s+'
    let l:static = 'static\s+'
    let l:method_declaration = l:visibility . '%(' . l:static . ')?function\s+'
    let l:method_usage = '%(\$this-\>|self::|static::)'
    let l:attribute_declaration = l:visibility . '%('. l:static . ')?\$'
    let l:attribute_usage = '%(\$this-\>|self::\$|static::\$)'
    let l:constant_declaration = l:visibility . 'const\s+'
    let l:constant_usage = '%(self::|static::)'

    if l:line =~ '\v%(' . l:method_declaration . '|' . l:method_usage . ')' . a:word . '\s*\(' " a method
      return s:t_method
    elseif l:line =~ '\v%(' . l:attribute_declaration . '|' . l:attribute_usage . ')' . a:word . '>' " an attribute
      return s:t_attribute
    elseif l:line =~ '\v%(' . l:constant_declaration . '|' . l:constant_usage . ')' . a:word . '>' " a constant
      return s:t_constant
    elseif l:line =~ '\vfunction\s+' . a:word . '\s*\('
      return s:t_function
    elseif l:line =~ '\v\$' . a:word . '>'
      return s:t_variable
    else return s:t_unknown
    endif
endfunction
" }}}

function! s:SaveView() " {{{
  let s:saved_view = winsaveview()
endfunction
" }}}

function! s:ResetView() " {{{
    if exists('s:saved_view')
        call winrestview(s:saved_view)
    endif
endfunction
" }}}
