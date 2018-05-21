let s:saved_registers = {}

" Save the state of a register
" Will erase any previous state for this register
function! phprefactor#registers#save(register) " {{{
  let s:saved_registers[a:register] = {
    \'value': getreg(a:register, 1),
    \'type':  getregtype(a:register)
    \}
endfunction " }}}

" Reset a register to his previous state
" Free the saved register
function! phprefactor#registers#restore(register) " {{{
  if !exists('s:saved_registers[a:register]')
    return
  endif

  call setreg(
    \a:register,
    \s:saved_registers[a:register].value,
    \s:saved_registers[a:register].type,
    \)

  unlet s:saved_registers[a:register]
endfunction " }}}
