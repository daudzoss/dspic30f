e2ontrap.o : e2ontrap.s
	elf-as e2ontrap.s --defsym B0REQUIRED1= --defsym EEPROM_SIZE=1024 -o e2ontrap.o
