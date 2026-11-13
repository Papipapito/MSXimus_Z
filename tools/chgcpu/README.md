# CHGCPU.COM

Utilidad de MSX-DOS (DOS1/DOS2/Nextor) para cambiar de CPU en un turbo R (perfil TR del MSXimus Z).
Usa las rutinas de la BIOS `CHGCPU` (0180h) y `GETCPU` (0183h) por CALSLT; nunca escribe el S1990.

    CHGCPU          muestra la CPU actual (Z80 / R800 ROM / R800 DRAM)
    CHGCPU Z80      cambia al Z80
    CHGCPU R800     cambia al R800 (modo DRAM, el normal)
    CHGCPU ROM      cambia al R800 en modo ROM
    CHGCPU /?       ayuda

Sin distinguir mayusculas. Al cambiar enciende el LED (bit 7) y vuelve a mostrar la CPU.
Si no es un turbo R (ID de la BIOS, 002Dh, distinto de 3) avisa y sale. Codigo de salida (_TERM en DOS2/Nextor): 0 bien, 1 error.

Build (pasmo, WSL Ubuntu-24.04): `sh build.sh` -> `CHGCPU.COM` aqui (y una copia en `files/tr_fase5b/`, la carpeta de entregas del desarrollo).

Las pruebas en openMSX (Panasonic_FS-A1ST, MSX-DOS 2 desde un directorio como disco A:) no van en esta copia.
