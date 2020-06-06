e2ontrap.o : e2ontrap.s
	elf-as e2ontrap.s -DB0REQUIRED1 -DEEPROM_SIZE=1024 -o e2ontrap.o
