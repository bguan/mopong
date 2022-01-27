import 'dart:math';

import 'dart:typed_data';

class NameGenerator {
  static const List<String> ANIMALS = [
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
    'Pigeon',
    'Hippo',
    'Lion',
    'Fox',
    'Rhino',
    'Eel',
    'Elephant',
    'Deer',
    'Dolphin',
    'Duck',
    'Seal',
    'Walrus',
    'Octopus',
    'Squid',
    'Salmon',
    'Worm',
    'Snail',
    'Shrimp',
    'Fish',
    'Whale',
    'Orca',
    'Bird',
    'Parrot',
    'Seagull',
    'Eagle',
    'Pelican',
    'Frog',
    'Toad',
    'Newt',
    'Dino',
    'Donkey',
    'Slug',
    'Ape',
    'Chimp',
    'Crab',
    'Lobster',
    'Bee',
    'Beetle',
    'Ant',
    'Hornet',
    'Butterfly',
    'Fly',
    'Moth',
    'Mosquito',
    'Kangaroo',
    'Giraffe',
    'Zebra',
    'Wolf',
  ];

  static const List<String> ADJECTIVES = [
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
    'Happy',
    'Sad',
    'Angry',
    'Calm',
    'Crazy',
    'Furry',
    'Scaly',
    'Prickly',
    'Smooth',
    'Bald',
    'Big',
    'Small',
    'Long',
    'Short',
    'Fat',
    'Skinny',
    'Heavy',
    'Light',
    'Slow',
    'Fast',
    'Smelly',
    'Tasty',
    'Clean',
    'Dirty',
    'Ugly',
    'Pretty',
    'Scary',
    'Lovely',
    'Friendly',
    'Hot',
    'Cold',
    'Warm',
    'Cool',
    'Strange',
    'Young',
    'Old',
    'Strong',
    'Weak',
    'Tall',
    'Lonely'
  ];

  static String genNewName(Uint8List addressByteIPv4) {
    int lastByte = addressByteIPv4.last;
    late final int animalIdx;
    late final int adjIdx;
    if (lastByte == 0) {
      var rng = new Random();
      animalIdx = rng.nextInt(ANIMALS.length);
      adjIdx = rng.nextInt(ADJECTIVES.length);
    } else {
      animalIdx = lastByte >> 4;
      adjIdx = lastByte & 0x0F;
    }
    return ADJECTIVES[adjIdx] + ' ' + ANIMALS[animalIdx];
  }
}
