all:		life.com life42.com


life.com:	life.asm
		nasm -f bin life.asm -o life.com

life42.com:	life_root42.asm
		nasm -f bin life_root42.asm -o life42.com

