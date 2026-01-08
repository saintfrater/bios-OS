

debug_puts:
.next:
						lodsb                    	; AL = *SI++
						test 			al, al
						jz   			.done
						
						mov				dx, DEBUG_PORT

						out				dx, al
						jmp  			.next
.done:
						ret
						
debug_putc:
.next:
						mov				dx, DEBUG_PORT
						out				dx, al
						ret						