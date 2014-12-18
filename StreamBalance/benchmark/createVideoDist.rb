#!/usr/bin/ruby
distribuicao = [0, 0, 0, 1, 1, 1, 2, 2, 3, 4]
for i in 1..100000
puts distribuicao[rand(10)]
end
