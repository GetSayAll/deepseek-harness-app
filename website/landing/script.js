const menuButton = document.querySelector('.menu-button')
const navigation = document.querySelector('.site-nav')

menuButton?.addEventListener('click', () => {
  const isOpen = menuButton.getAttribute('aria-expanded') === 'true'
  menuButton.setAttribute('aria-expanded', String(!isOpen))
  navigation?.classList.toggle('open', !isOpen)
})

navigation?.querySelectorAll('a').forEach((link) => {
  link.addEventListener('click', () => {
    menuButton?.setAttribute('aria-expanded', 'false')
    navigation.classList.remove('open')
  })
})

if (!window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
  document.documentElement.classList.add('motion-ready')
}
