import 'dart:math';

const animals = [
  'Rat',
  'Cow',
  'Tiger',
  'Rabbit',
  'Dragon',
  'Snake',
  'Horse',
  'Goat',
  'Monkey',
  'Chicken',
  'Dog',
  'Pig',
];
const colors = [
  'Red',
  'Orange',
  'Yellow',
  'Green',
  'Blue',
  'Magenta',
  'Purple',
  'Black',
  'White',
  'Gray',
];

String genName() {
  var rng = new Random();
  final animalIdx = rng.nextInt(100) % animals.length;
  final colorIdx = rng.nextInt(100) % colors.length;

  return colors[colorIdx] + ' ' + animals[animalIdx];
}
