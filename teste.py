# Algoritmo para calcular a média de notas de 10 alunos

# Ler as notas dos 10 alunos
n1 = float(input("Entre com a nota do 1º aluno: "))
n2 = float(input("Entre com a nota do 2º aluno: "))
n3 = float(input("Entre com a nota do 3º aluno: "))
n4 = float(input("Entre com a nota do 4º aluno: "))
n5 = float(input("Entre com a nota do 5º aluno: "))
n6 = float(input("Entre com a nota do 6º aluno: "))
n7 = float(input("Entre com a nota do 7º aluno: "))
n8 = float(input("Entre com a nota do 8º aluno: "))
n9 = float(input("Entre com a nota do 9º aluno: "))
n10 = float(input("Entre com a nota do 10º aluno: "))

# Calcular a média
media = (n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 + n9 + n10) / 10

# Exibir o resultado
print(f"A média da turma é: {media:.2f}")
