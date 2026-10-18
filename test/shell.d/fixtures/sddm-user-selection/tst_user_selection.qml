import QtQuick
import QtTest

TestCase {
  id: testCase
  name: "SddmUserSelection"
  width: 640
  height: 480
  visible: true
  when: windowShown

  ListModel {
    id: userModel
    property string lastUser: "alice"
    property int lastIndex: 0
    ListElement { name: "alice"; realName: "Alice" }
    ListElement { name: "bob"; realName: "Bob" }
    ListElement { name: "carol"; realName: "Carol" }
  }

  QtObject {
    id: sessionModel
    property int lastIndex: 0
    function rowCount() { return 0 }
  }

  QtObject {
    id: sddm
    signal loginFailed()
    signal loginSucceeded()
    property string submittedUser: ""
    function login(user, password, session) { submittedUser = user }
  }

  property var greeter: null

  function findItem(item, predicate) {
    if (predicate(item)) return item
    var children = item.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findItem(children[i], predicate)
      if (found) return found
    }
    return null
  }

  function initTestCase() {
    var component = Qt.createComponent(Qt.resolvedUrl("../../../../default/sddm/omarchy/Main.qml"))
    compare(component.status, Component.Ready, component.errorString())
    greeter = component.createObject(testCase, { width: 640, height: 480 })
    verify(greeter !== null)
  }

  function test_chooseUserAndAuthenticate() {
    tryCompare(greeter, "currentUser", "alice")
    var next = findItem(greeter, function(item) { return item.text === ">" })
    var previous = findItem(greeter, function(item) { return item.text === "<" })
    var password = findItem(greeter, function(item) { return item.echoMode === TextInput.Password })
    verify(next !== null && previous !== null && password !== null)
    verify(next.visible && previous.visible)

    password.text = "discard-this-test-input"
    mouseClick(next, next.width / 2, next.height / 2)
    tryCompare(greeter, "currentUser", "bob")
    compare(password.text, "")
    password.text = "test-only"
    keyClick(Qt.Key_Return)
    compare(sddm.submittedUser, "bob")

    sddm.loginFailed()
    compare(greeter.loginFailed, true)
    compare(password.text, "")
    sddm.loginSucceeded()
    compare(greeter.loginFailed, false)

    mouseClick(previous, previous.width / 2, previous.height / 2)
    tryCompare(greeter, "currentUser", "alice")
    mouseClick(previous, previous.width / 2, previous.height / 2)
    tryCompare(greeter, "currentUser", "carol")
    mouseClick(next, next.width / 2, next.height / 2)
    tryCompare(greeter, "currentUser", "alice")
  }
}
