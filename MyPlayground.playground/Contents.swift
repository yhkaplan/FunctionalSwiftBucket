import Foundation

// Examples from `Functional Swift` by objc.io

extension CharacterSet {
    func contains(_ c: Character) -> Bool {
        let scalars = String(c).unicodeScalars
        guard scalars.count == 1, let first = scalars.first else { return false }
        return contains(first)
    }
}

struct Parser<Result> {
    typealias Stream = String // Was CharacterView
    let parse: (Stream) -> (Result, Stream)?

    // Makes output easier to understand:
    // Transforms input string into character view, and turns the remainder in the
    // result back into a string
    func run(_ string: String) -> (Result, String)? {
        guard let (result, remainder) = parse(string) else { return nil }
        return (result, String(remainder))
    }

    // A `combinator` that executes a parser multiple times and returns the
    // results as an array
    var many: Parser<[Result]> {
        return Parser<[Result]> { input in
            var result: [Result] = []
            var remainder = input
            while let (element, newRemainder) = self.parse(remainder) {
                result.append(element)
                remainder = newRemainder
            }
            return (result, remainder)
        }
    }

    // Transforms a parser of one result type into a parser of another result type
    func map<T>(_ transform: @escaping (Result) -> T) -> Parser<T> {
        return Parser<T> { input in
            guard let (result, remainder) = self.parse(input) else { return nil }
            return (transform(result), remainder)
        }
    }

    // Sequence combinator to execute multiple different parsers consecutively
    func followed<A>(by other: Parser<A>) -> Parser<(Result, A)> {
        return Parser<(Result, A)> { input in
            guard let (result1, remainder1) = self.parse(input) else { return nil }
            guard let (result2, remainder2) = other.parse(remainder1) else { return nil }
            return ((result1, result2), remainder2)
        }
    }

    // Combines parsers (another combinator?) similar to an || operator
    func or(_ other: Parser<Result>) -> Parser<Result> {
        return Parser<Result> { input in
            return self.parse(input) ?? other.parse(input)
        }
    }

}

func char(matching condition: @escaping (Character) -> Bool) -> Parser<Character> {
    return Parser { input in
        guard let char = input.first, condition(char) else { return nil }
        return (char, String(input.dropFirst())) // Converting SubString to String here might be very inefficient
    }
}

let one = char { $0 == "1" }
one.run("123")

// A parser to check if a character is a decimalDigit
let digit = char { CharacterSet.decimalDigits.contains($0) }

// Running the above parser many times
digit.many.run("456")

let integerParser = digit.many.map { Int(String($0)) ?? 0 }
integerParser.run("12d3f33fd")

let multiplicationParser = integerParser
    .followed(by: char { $0 == "*"} )
    .followed(by: integerParser)
multiplicationParser.run("2*3")

func multiply(_ x: Int, _ op: Character, _ y: Int) -> Int {
    return x * y
}

// Turns non-currying func w/ 2 args to curried func,
// which is a more readable way of implementing funcs

// Curry convenience func for two parameters
func curry<A, B, C>(_ f: @escaping (A, B) -> C) -> (A) -> (B) -> C {
    return { a in { b in f(a, b) } }
}

// Overload for funcs with three parameters
func curry<A, B, C, D>(_ f: @escaping (A, B, C) -> D) -> (A) -> (B) -> (C) -> (D) {
    return { a in { b in { c in f(a, b, c) } } }
}

let curriedMultiply = curry(multiply)
// How this would look w/o convenience curry func
//func curriedMultiply(_ x: Int) -> (Character) -> (Int) -> Int {
//    return { op in
//        return { y in
//            return x * y
//        }
//    }
//}

// Example of call site of curriedMultiply
curriedMultiply(2)("*")(3)

let p1 = integerParser.map(curriedMultiply)
let p2 = p1.followed(by: char { $0 == "*" })
let p3 = p2.map { f, op in f(op) }
let p4 = p3.followed(by: integerParser)
let p5 = p4.map { f, y in f(y) }

let multiplication = integerParser.map(curriedMultiply)
    .followed(by: char { $0 == "*" })
    .map { f, op in f(op) }
    .followed(by: integerParser)
    .map { f, y in f(y) }


precedencegroup SequencePrecedence {
    associativity: left
    higherThan: AdditionPrecedence
}

infix operator <*>: SequencePrecedence

func <*><A, B>(lhs: Parser<(A) -> B>, rhs: Parser<A>) -> Parser<B> {
    return lhs.followed(by: rhs).map { f, x in f(x) }
}

let mult4 = integerParser.map(curriedMultiply) <*> char { $0 == "*" } <*> integerParser

// Apply operator, `map` in reverse order
infix operator <^>: SequencePrecedence
func <^> <A, B>(lhs: @escaping (A) -> B, rhs: Parser<A>) -> Parser<B> {
    return rhs.map(lhs)
}

let mult5 = curriedMultiply <^> integerParser <*> char { $0 == "*" } <*> integerParser

infix operator *>: SequencePrecedence
func *><A, B>(lhs: Parser<A>, rhs: Parser<B>) -> Parser<A> {
    return curry({x, _ in x}) <^> lhs <*> rhs
}


let star = char { $0 == "*" }
let plus = char { $0 == "+" }
let starOrPlus = star.or(plus)
starOrPlus.run("+")

infix operator <|>
func <|><A>(lhs: Parser<A>, rhs: Parser<A>) -> Parser<A> {
    return lhs.or(rhs)
}

(star <|> plus).run("+")


extension Parser {
    // Tries to apply a parser one or more times
    var many1: Parser<[Result]> {
        return { x in { manyX in [x] + manyX } } <^> self <*> self.many
    }

    // Same as above but w/ reformatted currying
    var many2: Parser<[Result]> {
        return curry({ [$0] + $1 }) <^> self <*> self.many
    }
}

// optionalTransform applicative functor
func <*><A, B>(optionalTransform: ((A) -> B)?, optionalValue: A?) -> B? {
    guard let transform = optionalTransform, let value = optionalValue else { return nil }
    return transform(value)
}

// Example of usage
func addOptionals(x: Int?, y: Int?) -> Int? {
    return curry(+) <*> x <*> y
}

precedencegroup LeftApplyPrecedence {
    associativity: left
    higherThan: AssignmentPrecedence
    lowerThan: TernaryPrecedence
}

infix operator |> : LeftApplyPrecedence

func |> <T, U>(value: T, function: ((T) -> U)) -> U {
    return function(value)
}

precedencegroup FunctionCompositionPrecedence {
    associativity: right
    higherThan: LeftApplyPrecedence
}

infix operator >>>: FunctionCompositionPrecedence

// Compose two functions left to right
func >>><A, B, C>(f: @escaping (A) -> B, g: @escaping (B) -> C) -> (A) -> C {
    return { (a: A) -> C in g(f(a)) }
}
