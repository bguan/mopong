import 'dart:math';

const animals = [
  'Rat', 'Cow', 'Tiger', 'Rabbit', 'Dragon', 
  'Snake', 'Horse', 'Goat', 'Monkey', 'Chicken', 
  'Dog', 'Pig', 'Pigeon', 'Hippo', 'Lion',
  'Fox', 'Rhino', 'Eel', 'Elephant', 'Deer', 
  'Dolphin', 'Duck', 'Seal', 'Walrus', 'Octopus',
  'Squid', 'Salmon', 'Worm', 'Snail', 'Shrimp',
  'Fish', 'Whale', 'Orca', 'Bird', 'Parrot',
  'Seagull', 'Eagle', 'Pelican', 'Frog', 'Toad',
  'Newt', 'Dino', 'Donkey', 'Slug', 'Ape',
  'Chimp', 'Crab', 'Lobster', 'Bee', 'Beetle',
  'Ant', 'Hornet', 'Butterfly', 'Fly', 'Moth',
  'Mosquito', 'Kangaroo', 'Giraffe', 'Zebra', 'Wolf',
];
const adjectives = [
  'Red', 'Orange', 'Yellow', 'Green', 'Blue',
  'Magenta', 'Purple', 'Black', 'White', 'Gray',
  'Happy', 'Sad', 'Angry', 'Calm', 'Crazy',
  'Furry', 'Scaly', 'Prickly', 'Smooth', 'Bald',
  'Big', 'Small', 'Long', 'Short', 'Fat',
  'Skinny', 'Heavy', 'Light', 'Slow', 'Fast',
  'Smelly', 'Tasty', 'Clean', 'Dirty', 'Ugly',
  'Pretty', 'Scary', 'Lovely', 'Friendly', 'Hot',
  'Cold', 'Warm', 'Cool', 'Strange', 'Young',
  'Old', 'Strong', 'Weak', 'Tall', 'Lonely'
];

String genName() {
  var rng = new Random();
  final animalIdx = rng.nextInt(animals.length);
  final adjIdx = rng.nextInt(adjectives.length);

  return adjectives[adjIdx] + ' ' + animals[animalIdx];
}
