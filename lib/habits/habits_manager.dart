import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:HabitMind/constants.dart';
import 'package:HabitMind/habits/habit.dart';
import 'package:HabitMind/model/backup.dart';
import 'package:HabitMind/model/habit_data.dart';
import 'package:HabitMind/model/HabitMind_model.dart';
import 'package:HabitMind/notifications.dart';
import 'package:HabitMind/statistics/statistics.dart';

class HabitsManager extends ChangeNotifier {
  final HabitMindModel _HabitMindModel = HabitMindModel();
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey =
      GlobalKey<ScaffoldMessengerState>();

  late List<Habit> allHabits = [];
  bool _isInitialized = false;

  Habit? deletedHabit;
  Queue<Habit> toDelete = Queue();

  void initialize() async {
    await initModel();
    await Future.delayed(const Duration(seconds: 5));
    notifyListeners();
  }

  resetHabitsNotifications() {
    resetNotifications(allHabits);
  }

  initModel() async {
    await _HabitMindModel.initDatabase();
    allHabits = await _HabitMindModel.getAllHabits();
    _isInitialized = true;
    notifyListeners();
  }

  GlobalKey<ScaffoldMessengerState> get getScaffoldKey {
    return _scaffoldKey;
  }

  void hideSnackBar() {
    _scaffoldKey.currentState!.hideCurrentSnackBar();
  }

  createBackup() async {
    try {
      var file = await Backup.writeBackup(allHabits);
      final params = SaveFileDialogParams(
        sourceFilePath: file.path,
        mimeTypesFilter: ['application/json'],
      );
      await FlutterFileDialog.saveFile(params: params);
    } catch (e) {
      showErrorMessage('ERROR: Creating backup failed.');
    }
  }

  loadBackup() async {
    try {
      const params = OpenFileDialogParams(
        fileExtensionsFilter: ['json'],
        mimeTypesFilter: ['application/json'],
      );
      final filePath = await FlutterFileDialog.pickFile(params: params);
      if (filePath == null) {
        return;
      }
      final json = await Backup.readBackup(filePath);
      List<Habit> habits = [];
      jsonDecode(json).forEach((element) {
        habits.add(Habit.fromJson(element));
      });
      await _HabitMindModel.useBackup(habits);
      removeNotifications(allHabits);
      allHabits = habits;
      resetNotifications(allHabits);
      notifyListeners();
    } catch (e) {
      showErrorMessage('ERROR: Restoring backup failed.');
    }
  }

  resetNotifications(List<Habit> habits) {
    for (var element in habits) {
      if (element.habitData.notification) {
        var data = element.habitData;
        setHabitNotification(data.id!, data.notTime, 'HabitMind', data.title);
      }
    }
  }

  removeNotifications(List<Habit> habits) {
    for (var element in habits) {
      disableHabitNotification(element.habitData.id!);
    }
  }

  showErrorMessage(String message) {
    _scaffoldKey.currentState!.hideCurrentSnackBar();
    _scaffoldKey.currentState!.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: HabitMindColors.red,
      ),
    );
  }

  List<Habit> get getAllHabits {
    return allHabits;
  }

  bool get isInitialized {
    return _isInitialized;
  }

  reorderList(oldIndex, newIndex) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }
    Habit moved = allHabits.removeAt(oldIndex);
    allHabits.insert(newIndex, moved);
    updateOrder();
    _HabitMindModel.updateOrder(allHabits);
    notifyListeners();
  }

  addEvent(int id, DateTime dateTime, List event) {
    _HabitMindModel.insertEvent(id, dateTime, event);
  }

  deleteEvent(int id, DateTime dateTime) {
    _HabitMindModel.deleteEvent(id, dateTime);
  }

  addHabit(
      String title,
      bool twoDayRule,
      String cue,
      String routine,
      String reward,
      bool showReward,
      bool advanced,
      bool notification,
      TimeOfDay notTime,
      String sanction,
      bool showSanction,
      String accountant) {
    Habit newHabit = Habit(
      habitData: HabitData(
        position: allHabits.length,
        title: title,
        twoDayRule: twoDayRule,
        cue: cue,
        routine: routine,
        reward: reward,
        showReward: showReward,
        advanced: advanced,
        events: SplayTreeMap<DateTime, List>(),
        notification: notification,
        notTime: notTime,
        sanction: sanction,
        showSanction: showSanction,
        accountant: accountant,
      ),
    );
    _HabitMindModel.insertHabit(newHabit).then(
      (id) {
        newHabit.setId = id;
        allHabits.add(newHabit);
        if (notification) {
          setHabitNotification(id, notTime, 'HabitMind', title);
        } else {
          disableHabitNotification(id);
        }
        notifyListeners();
      },
    );
    updateOrder();
  }

  editHabit(HabitData habitData) {
    Habit? hab = findHabitById(habitData.id!);
    if (hab == null) return;
    hab.habitData.title = habitData.title;
    hab.habitData.twoDayRule = habitData.twoDayRule;
    hab.habitData.cue = habitData.cue;
    hab.habitData.routine = habitData.routine;
    hab.habitData.reward = habitData.reward;
    hab.habitData.showReward = habitData.showReward;
    hab.habitData.advanced = habitData.advanced;
    hab.habitData.notification = habitData.notification;
    hab.habitData.notTime = habitData.notTime;
    hab.habitData.sanction = habitData.sanction;
    hab.habitData.showSanction = habitData.showSanction;
    hab.habitData.accountant = habitData.accountant;
    _HabitMindModel.editHabit(hab);
    if (habitData.notification) {
      setHabitNotification(
          habitData.id!, habitData.notTime, 'HabitMind', habitData.title);
    } else {
      disableHabitNotification(habitData.id!);
    }
    notifyListeners();
  }

  String getNameOfHabit(int id) {
    Habit? hab = findHabitById(id);
    return (hab != null) ? hab.habitData.title : "";
  }

  Habit? findHabitById(int id) {
    Habit? result;
    for (var hab in allHabits) {
      if (hab.habitData.id == id) {
        result = hab;
      }
    }
    return result;
  }

  deleteHabit(int id) {
    deletedHabit = findHabitById(id);
    allHabits.remove(deletedHabit);
    toDelete.addLast(deletedHabit!);
    Future.delayed(const Duration(seconds: 4), () => deleteFromDB());
    _scaffoldKey.currentState!.hideCurrentSnackBar();
    _scaffoldKey.currentState!.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: const Text("Habit deleted."),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            undoDeleteHabit(deletedHabit!);
          },
        ),
      ),
    );
    updateOrder();
    notifyListeners();
  }

  undoDeleteHabit(Habit del) {
    toDelete.remove(del);
    if (deletedHabit != null) {
      if (deletedHabit!.habitData.position < allHabits.length) {
        allHabits.insert(deletedHabit!.habitData.position, deletedHabit!);
      } else {
        allHabits.add(deletedHabit!);
      }
    }

    updateOrder();
    notifyListeners();
  }

  Future<void> deleteFromDB() async {
    if (toDelete.isNotEmpty) {
      disableHabitNotification(toDelete.first.habitData.id!);
      _HabitMindModel.deleteHabit(toDelete.first.habitData.id!);
      toDelete.removeFirst();
    }
    if (toDelete.isNotEmpty) {
      Future.delayed(const Duration(seconds: 1), () => deleteFromDB());
    }
  }

  updateOrder() {
    int iterator = 0;
    for (var habit in allHabits) {
      habit.habitData.position = iterator++;
    }
  }

  Future<AllStatistics> getFutureStatsData() async {
    return await Statistics.calculateStatistics(allHabits);
  }
}