"
" VIM PHP Refactoring Toolbox
"
" Maintainer: Pierrick Charron <pierrick@adoy.net>
" URL: https://github.com/adoy/vim-php-refactoring-toolbox
" License: MIT
" Version: 1.0.3
"

let s:exception = {
    \ 'abort': 'Interrupt',
\}

let s:context = {
    \ 'scope':     {'start': 0, 'end': 0},
    \ 'class':     {'start': 0, 'end': 0},
    \ 'function':  {'start': 0, 'end': 0, 'docblock': 0},
    \ 'selection': {'start': 0, 'end': 0, 'text': ''},
\}

function! PhpTest() range " {{{
    try
        call s:SaveView()

        let s:context.class           = s:FindClassPositions(line('.'))
        let s:context.function        = s:PhpFindFunctionOrMethodPositions(line('.'))
        let s:context.scope           = s:FindScopePositions(line('.'))
        let s:context.selection.start = a:firstline
        let s:context.selection.end   = a:lastline
        let s:context.selection.text  = s:GetSelectedText()

        " Creates an "origin" mark for where the user was
        normal! mo

        " Creates an "extract" mark for where the extract method should be put
        let l:extract_linenr = s:context.function.start ? s:context.function.end : line('$')
        execute l:extract_linenr 'mark e'

        let l:new_name         = s:AskNewFunctionOrMethodName()
        let l:arguments        = s:PhpExtractAguments()
        let l:return_variables = s:PhpExtractReturnVariables()

        call s:ReplaceSelectionByFunctionOrMethodCall(l:new_name, l:arguments, l:return_variables)
        call s:InsertExtractedFunctionOrMethod(l:new_name, l:arguments, l:return_variables)

    catch /^\(Vim:\)\?Interrupt$/
        " Do nothing, the user abort the operation
    finally
        call s:ResetView()
    endtry
endfunction " }}}

function! s:ReplaceSelectionByFunctionOrMethodCall(name, arguments, return_variables) " {{{
    let l:function_statement = s:GenerateFunctionOrMethodCall(a:name, a:arguments, a:return_variables)
    let l:pattern            = escape(s:Trim(s:context.selection.text), '\.*$^~[')
    let l:pattern            = substitute(l:pattern, '\_s\+', '\\_s\\+', 'g')
    let l:range = s:context.class.start
        \ ? s:context.class.start . ',' . s:context.class.end
        \ : s:context.scope.start . ',' . s:context.scope.end

    execute l:range . 's/' . l:pattern . '/' . l:function_statement . '/e'
endfunction " }}}

function! s:InsertExtractedFunctionOrMethod(name, arguments, return_variables) " {{{
    let l:implementation = s:GenerateFunctionOrMethodImplementation(a:name, a:arguments, a:return_variables)

    call phprefactor#registers#save('=')
    execute line("'e") 'put =nr2char(10) . l:implementation'
    execute line("'e") + 2 'mark e'
    call phprefactor#registers#restore('=')
    normal! ='[
endfunction " }}}

function! s:GenerateFunctionOrMethodCall(name, arguments, return_variables) " {{{
    let l:name = (s:context.class.start ? '$this->' : '') .  a:name

    let l:variables        = map(copy(a:arguments), '"$" . v:val.name')
    let l:arguments_string = join(l:variables, ', ')

    let l:number_of_return_variables = len(a:return_variables)
    if 0 == l:number_of_return_variables
        let l:return_string = ''
    elseif 1 == l:number_of_return_variables
        let l:return_string = '$' . a:return_variables[0].name . ' = '
    else
        let l:returns       = map(copy(a:return_variables), '"$" . v:val.name')
        let l:return_string = printf('list(%s) = ' . join(l:returns, ', '))
    endif

    return printf('%s%s(%s);', l:return_string, l:name, l:arguments_string)
endfunction " }}}

function! s:GenerateFunctionOrMethodImplementation(name, arguments, return_variables) " {{{
    let l:function = 'function'

    if s:context.class.start
        let l:function = 'public ' . l:function
    endif

    let l:return_string = s:FormatReturnVariables(a:return_variables)

    return printf(
        \ "%s %s(%s)\n{\n%s%s\n}",
        \ l:function,
        \ a:name,
        \ join(s:FormatArguments(a:arguments), ', '),
        \ s:context.selection.text,
        \ !empty(l:return_string) ? "\n" . l:return_string : ''
    \)
endfunction " }}}

function! s:FormatArguments(arguments) " {{{
    let l:formated_arguments = []
    for l:argument in a:arguments
        let l:formated_argument  = l:argument.nullable ? '?' : ''
        let l:formated_argument .= l:argument.type ? l:argument.type . ' ' : ''
        let l:formated_argument .= l:argument.reference ? '&' : ''
        let l:formated_argument .= '$' . l:argument.name

        call add(l:formated_arguments, l:formated_argument)
    endfor

    return l:formated_arguments
endfunction " }}}

function! s:FormatReturnVariables(variables) " {{{
    let l:number_of_return_variables = len(a:variables)

    if 0 == l:number_of_return_variables
        let l:return = ''
    else
        let l:return = 'return '

        if 1 == l:number_of_return_variables
            let l:return .= '$' . a:variables[0].name
        else
            let l:variables  = map(copy(a:variables), '"$" . v:val.name')
            let l:return    .= printf('array(%s)', join(l:variables, ', '))
        endif

        let l:return .= ';'
    endif

    return l:return
endfunction " }}}

function! s:PhpExtractAguments() " {{{
    let l:before_selection   = join(getline(s:context.scope.start, s:context.selection.start - 1), "\n")
    let l:function_arguments = s:GetFunctionOrMethodArguments(getline(s:context.function.start))

    let l:arguments = []
    for l:variable in s:PhpMatchAllStr(s:context.selection.text, s:php_regex_local_var_2)
        let l:variable = l:variable[1:] " Removes the $ sign

        if exists('l:function[l:variable]')
            call add(l:arguments, l:function_arguments[l:variable])
        elseif match(l:before_selection, '\$\<' . l:variable . '\>') > 0
            call add(l:arguments, s:CreateArgument(l:variable))
        endif
    endfor

    return l:arguments
endfunction " }}}

function! s:PhpExtractReturnVariables() " {{{
    let l:after_selection = join(getline(s:context.selection.end + 1, s:context.scope.end), "\n")

    let l:return_variables = []
    for l:variable in s:PhpMatchAllStr(s:context.selection.text, s:php_regex_local_var_2)
        let l:variable = l:variable[1:] " Removes the $ sign

        if -1 != match(l:after_selection, '\$\<' . l:variable . '\>')
            call add(l:return_variables, s:CreateArgument(l:variable))
        endif
    endfor

    return l:return_variables
endfunction " }}}

function! s:CreateArgument(name, ...) " {{{
    return {
        \ 'type':      get(a:000, 0, ''),
        \ 'nullable':  get(a:000, 1, ''),
        \ 'reference': get(a:000, 2, ''),
        \ 'name':      a:name,
    \}
endfunction " }}}

function! s:GetFunctionOrMethodArguments(declaration) " {{{
    let l:oneline_declaration = substitute(a:declaration,  '\_s\+', ' ', 'ge')
    let l:arguments_string    = substitute(l:oneline_declaration, '.*(\s*\(.*\)\s*)', '\1', 'e')

    let l:arguments = {}
    for l:argument in split(l:arguments_string, '\s*,\s*')
        let l:parts = matchlist(l:argument, s:php_regex_argument)
        echomsg l:argument
        echomsg string(l:parts)
        let l:arguments[l:parts[4]] = s:CreateArgument(l:parts[4], l:parts[2], l:parts[1], l:parts[3])
    endfor

    return l:arguments
endfunction " }}}

function! s:FindScopePositions(linenr) " {{{
    if s:context.function.start
        return s:context.function
    elseif s:context.class.start
        return s:context.class
    else
        return {'start': 1, 'end': search(s:php_regex_func_line, 'nW')}
    endif
endfunction " }}}

function! s:PhpFindFunctionOrMethodPositions(linenr) " {{{
    let l:positions = {'start': 0, 'end': 0, 'docblock': 0}
    let l:start     = s:PhpFindFunctionOrMethodStart(a:linenr)

    if !l:start " There is no function declaration before the line
        return l:positions
    endif

    let l:end = s:PhpFindFunctionOrMethodEnd(l:start)

    " If false then the line is not inside a function
    if l:start <= a:linenr && a:linenr <= l:end
        let l:positions.start    = l:start
        let l:positions.end      = l:end
        let l:positions.docblock = s:PhpFindDocblock(l:start)
    endif

    return l:positions
endfunction " }}}

function! s:PhpFindFunctionOrMethodStart(linenr) " {{{
    let l:start = a:linenr

    while getline(l:start) !~ s:php_regex_func_line
        let l:start -= 1

        if 0 == l:start
            return 0
        endif
    endwhile

    return l:start
endfunction " }}}

function! s:PhpFindFunctionOrMethodEnd(start) " {{{
    let l:curpos_save = s:SaveCurpos()

    call cursor(a:start, 1)
    " Do not use ]M, it does not work for procedural functions
    normal! ]m%

    let l:end = line('.')

    call cursor(l:curpos_save)

    return l:end
endfunction " }}}

function! s:PhpFindDocblock(linenr) " {{{
    for l:start in range(a:linenr, 1, -1)
        let l:line = getline(l:start)

        if empty(s:Trim(l:line)) || l:line =~ '^\s*\*'
            continue
        endif

        if l:line =~ s:php_regex_docblock_start
            return l:start
        endif

        return 0
    endfor

    return 0
endfunction " }}}

function! s:AskNewFunctionOrMethodName() " {{{
    if s:context.class.start " Not in a class
        return s:AskNewMethodName()
    endif

    return s:AskNewFunctionName()
endfunction " }}}

function! s:AskNewFunctionName() " {{{
    let l:name = s:InputDialog('Name of the new function: ')

    if empty(l:name)
        throw s:exception.abort
    endif

    if !s:CheckIfNewNameAlreadyExists('^\s*function\s\+\<' . l:name . '\>')
        throw s:exception.abort
    endif

    return l:name
endfunction " }}}

function! s:AskNewMethodName() " {{{
    let l:name = s:InputDialog('Name of the new method: ')

    if empty(l:name)
        throw s:exception.abort
    endif

    if !s:CheckIfNewNameAlreadyExists(
        \ s:php_regex_func_line . '\<' . l:name . '\>',
        \ s:context.class.start,
        \ s:context.class.end
    \)
        throw s:exception.abort
    endif

    return l:name
endfunction " }}}

function! s:AskAboutVisibility() " {{{
    if 0 != g:vim_php_refactoring_auto_validate_visibility
        return g:vim_php_refactoring_default_method_visibility
    endif

    let l:visibilities = {
        \ 0: g:vim_php_refactoring_default_method_visibility,
        \ 1: 'public',
        \ 2: 'protected',
        \ 3: 'private',
        \ 4: ''
    \}

    let l:index = inputlist([
        \ 'Visibility (default is ' . g:vim_php_refactoring_default_method_visibility . ')',
        \ '1. public', '2. protected', '3. private', '4. none'
    \])

    if !has_key(l:visibilities, l:index)
        call s:PhpEchoError('Invalid choice')
        return AskAboutVisibility()
    endif

    return l:visibilities[l:index]
endfunction " }}}

function! s:FindClassPositions(linenr) " {{{
    try
        let l:positions   = {'start': 0, 'end': 0}
        let l:curpos_save = s:SaveCurpos()

        if 0 != search(s:php_regex_class_line, 'bW')
            let l:positions.start = line('.')

            call search('{', 'W')
            exec "keepjumps normal! %"

            let l:positions.end = line('.')
        endif
    finally
        call cursor(l:curpos_save)
    endtry

    return l:positions
endfunction " }}}

function! s:InputDialog(message) " {{{
    return s:Trim(inputdialog(a:message))
endfunction " }}}

function! s:CheckIfNewNameAlreadyExists(pattern, ...) " {{{
    let l:end = exists('a:1') ? a:1 : 0
    let l:end   = exists('a:2') ? a:2 : line('$')

    if s:PhpSearchInRange(a:pattern, 'n', l:end, l:end)
        call s:PhpEchoError(l:newName . ' seems to already exist. Rename anyway ?')
        if 1 != inputlist(['0. No', '1. Yes'])
            return v:false
        endif
    endif

    return v:true
endfunction " }}}

function! s:SaveCurpos() " {{{
    let l:curpos = getcurpos()
    call remove(l:curpos, 0)

    return l:curpos
endfunction " }}}

if !hasmapto('PhpTest')
    vnoremap <unique> <Leader>tt :call PhpTest()<CR>
endif

function! s:GetParametersForExtractedCode(selection, selection_strat, selection_end) " {{{
    call phprefactor#registers#save('p')

    let l:parameters = {}

    try
        keepjumps normal! [[f("pyi(
        let l:startLine = line('.')
        " Do not use ]M directly because it does not work for functions
        keepjumps normal! ]m%
        let l:stopLine = line('.')

        let l:beforeExtract = join(getline(l:startLine, a:selection_start - 1))
        let l:afterExtract  = join(getline(a:selection_end + 1, l:stopLine))

        for l:var in s:PhpMatchAllStr(a:selection, s:php_regex_local_var)
            " Don't bother with a complex regexp, the previous line already did it
            let l:var_pattern = substitute(l:var, '$\(.\+\)', '$\\<\1\\>', '')

            if match(l:beforeExtract, l:var_pattern) > 0
                let l:parameters[l:var]['in'] = 1

                l:type_pattern = '\(' . s:php_regex_type . '\)'        " Capture the type
                    \ . '\%(\(' . s:php_regex_reference . '\)\|\s\+\)' " Capture the '&' if present
                    \ . l:var_pattern                                  " For the current variable
                let l:matches = matchlist(@p, l:type_pattern)

                if !empty(l:matches) " The function argument provides additional information
                    let l:parameters[l:var]['type'] = l:matches[1]
                    let l:parameters[l:var]['ref']  = !empty(l:matches[2])
                endif
            endif
            if match(l:afterExtract, l:var_pattern) > 0
                let l:parameters[l:var]['out'] = 1
            endif
        endfor
    endtry

    call phprefactor#registers#restore('p')
    return l:parameters
endfunction
" }}}

function! s:GetSelectedText() " {{{
    call phprefactor#registers#save('"')

    " Reselect the selection and copy it to the unnamed register (")
    normal! gvy

    let l:selection = @"

    call phprefactor#registers#restore('"')

    return l:selection
endfunction
" }}}

function! s:Trim(str) " {{{
    return substitute(a:str, '^\_s*\(.\{-\}\)\_s*$', '\1', '')
endfunction
" }}}

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
let s:php_regex_word           = '[a-zA-Z_\x7f-\xff][a-zA-Z0-9_\x7f-\xff]*'
let s:php_regex_type           = '\%(\%(\(?\)\s*\)\?\([\\a-zA-Z_\x7f-\xff][\\a-zA-Z0-9_\x7f-\xff]*\)\)\?\%(\s*\(&\)\s*\)\?'
let s:php_regex_local_var_2    = '\$\(\%(this->\)\@!' . s:php_regex_word . '\)'
let s:php_regex_argument       = s:php_regex_type . s:php_regex_local_var_2
let s:php_regex_reference      = '\%(\s\+&\|&\s\+\|\s\+&\s\+\)'

let s:php_regex_phptag_line    = '<?\%(php\)\?'
let s:php_regex_ns_line        = '^namespace\_s\+[\\_A-Za-z0-9]*\_s*[;{]'
let s:php_regex_use_line       = '^use\_s\+[\\_A-Za-z0-9]\+\%(\_s\+as\_s\+[_A-Za-z0-9]\+\)\?\_s*\%(,\_s\+[\\_A-Za-z0-9]\+\%(\_s\+as\_s\+[_A-Za-z0-9]\+\)\?\_s*\)*;'
let s:php_regex_class_line     = '^\%(\%(final\s\+\|abstract\s\+\)\?class\>\|trait\>\)'
let s:php_regex_const_line     = '^\s*const\s\+[^;]\+;'
let s:php_regex_member_line    = '^\s*\%(\%(private\|protected\|public\|static\)\s*\)\+\$'
let s:php_regex_func_line      = '^\s*\%(\%(private\|protected\|public\|static\|abstract\)\s\+\)*function\_s\+'
let s:php_regex_docblock_start = '^\s*\/\*\*'

let s:php_regex_local_var      = '\$\<\%(this\>\)\@![A-Za-z0-9]*'
let s:php_regex_assignment     = '+=\|-=\|*=\|/=\|=\~\|!=\|='
let s:php_regex_fqcn           = '[\\_A-Za-z0-9]*'
let s:php_regex_cn             = '[_A-Za-z0-9]\+'
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

function! PhpInline() " Inlines an assignation {{{
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

" vim: ts=4 sw=4 et fdm=marker
