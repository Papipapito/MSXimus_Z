; V9968ON.COM - prepara el V9968 del MSXimus Z para el software de la generacion B (DEVCON, V9968DM)
; 1) OUT (9Ch),0: desbloquea R#20/R#21 (generacion C: tras el reset estan bloqueados)
; 2) R#21 = 0: modo V9968 (LRMM/LFMC, 256 KB, ID 3). En un chip de la generacion B lo hacia la BIOS al
;    arrancar; en el Z esa escritura se ignora por el bloqueo y el chip sigue en modo V9958. V9968DM no
;    escribe R#21 y sin esto su LRMM no hace nada (el logo no gira).
; Un reset vuelve a bloquear R#20/R#21 y a poner el modo V9958.
; pasmo V9968ON.ASM V9968ON.COM
        org     0100h
        di
        xor     a
        out     (9Ch),a         ; puerto 4: bit 7 = 0, desbloqueo (bits 1-0 = 0: no borra banderas)
        out     (99h),a         ; R#21 = 0
        ld      a,80h+21
        out     (99h),a
        ei
        ret
